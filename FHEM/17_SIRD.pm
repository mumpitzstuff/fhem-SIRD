##############################################################################
#
#     17_SIRD.pm
#
#     Author: Achim Winkler
#
##############################################################################

package main;

use strict;
use warnings;
use utf8;
use Encode qw(encode_utf8 decode_utf8);
use XML::Bare qw(xmlin forcearray);
use URI::Escape;
use HTTP::Daemon;
use IO::Socket::INET;
use Data::Dumper;

use HttpUtils;
use Blocking;
use SetExtensions;

# global variables
my @SIRD_queue;


sub SIRD_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn}      = 'SIRD_Define';
  $hash->{UndefFn}    = 'SIRD_Undefine';
  $hash->{ShutdownFn} = 'SIRD_Undefine';
  $hash->{NotifyFn}   = 'SIRD_Notify';
  $hash->{SetFn}      = 'SIRD_Set';
  $hash->{GetFn}      = 'SIRD_Get';
  $hash->{AttrFn}     = 'SIRD_Attr';
  $hash->{AttrList}   = 'disable:0,1 '.
                        'autoLogin:0,1 '.
                        'compatibilityMode:0,1 '.
                        'playCommands '.
                        'maxNavigationItems '.
                        'ttsInput '.
                        'ttsLanguage '.
                        'ttsVolume '.
                        'ttsWaitTimes '.
                        'streamInput '.
                        'streamWaitTimes '.
                        'streamPath '.
                        'streamPort '.
                        'updateAfterSet:0,1 '.
                        'notifications:0,1 '.
                        $readingFnAttributes;

  return undef;
}


sub SIRD_Define($$)
{
  my ($hash, $def) = @_;
  my @args = split("[ \t][ \t]*", $def);

  return 'Usage: define <name> SIRD <ip> <pin> <interval>'  if (@args < 4);

  my ($name, $type, $ip, $pin, $interval) = @args;

  return 'Please enter a valid ip address ('.$ip.').' if ($ip !~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/);
  return 'Please enter a valid pin (4 digits).' if ($pin !~ /^\d\d\d\d$/);
  return 'The update interval must be a number and has to be at least 5s if compatibility mode is disabled and '.
         '10s if enabled (the interval will be set to 10s automatically if compatibility mode is enabled).' if (($interval !~ /^\d+$/) || ($interval < 5));

  $hash->{NOTIFYDEV} = 'global';
  $hash->{IP} = $ip;
  $hash->{PIN} = $pin;
  $hash->{INTERVAL} = $interval;
  $hash->{VERSION} = '1.1.6';

  delete($hash->{helper}{suspendUpdate});
  delete($hash->{helper}{notifications});
  delete($hash->{helper}{sid});

  readingsSingleUpdate($hash, 'state', 'Initialized', 1);

  Log3 $name, 3, $name.' defined with ip '.$ip.' and interval '.$interval;

  return undef;
}


sub SIRD_Undefine($$)
{
  my ($hash, $arg) = @_;

  delete($hash->{helper}{suspendUpdate});
  delete($hash->{helper}{notifications});
  delete($hash->{helper}{sid});

  RemoveInternalTimer($hash);
  SetExtensionsCancel($hash);
  BlockingKill($hash->{helper}{PID_NAVIGATION}) if (defined($hash->{helper}{PID_NAVIGATION}));
  BlockingKill($hash->{helper}{PID_SPEAK}) if (defined($hash->{helper}{PID_SPEAK}));
  BlockingKill($hash->{helper}{PID_STREAM}) if (defined($hash->{helper}{PID_STREAM}));
  BlockingKill($hash->{helper}{PID_WEBSERVER}) if (defined($hash->{helper}{PID_WEBSERVER}));
  HttpUtils_Close($hash);

  return undef;
}


sub SIRD_Notify($$)
{
  my ($hash, $dev) = @_;
  my $name = $hash->{NAME};

  return if ('global' ne $dev->{NAME});
  return if (!grep(m/^INITIALIZED|REREADCFG$/, @{$dev->{CHANGED}}));

  if (IsDisabled($name))
  {
    readingsSingleUpdate($hash, 'state', 'disabled', 0);
  }
  else
  {
    if (!defined(InternalVal($name, 'MODEL', undef)) ||
        !defined(InternalVal($name, 'UDN', undef)))
    {
      my $ip = InternalVal($name, 'IP', undef);

      if (defined($ip))
      {
        my $param = {
                      url        => 'http://'.$ip.':8080/dd.xml',
                      timeout    => 6,
                      hash       => $hash,
                      method     => 'GET',
                      callback   => \&SIRD_ParseDeviceInfo
                    };

        HttpUtils_NonblockingGet($param);
      }
    }

    SIRD_SetNextTimer($hash, int(rand(15)));
  }

  return undef;
}


sub SIRD_Attr($$$$) {
  my ($command, $name, $attribute, $value) = @_;
  my $hash = $defs{$name};

  if ('set' eq $command)
  {
    if ('disable' eq $attribute)
    {
      if ('1' eq $value)
      {
        readingsSingleUpdate($hash, 'state', 'disabled', 1);
      }
      else
      {
        SIRD_SetNextTimer($hash, 0);

        readingsSingleUpdate($hash, 'state', 'Initialized', 1);
      }
    }
    elsif ('playCommands' eq $attribute)
    {
      my $fail = 0;
      my @playCommands = split('\s*,\s*' , $value);

      if (5 == scalar(@playCommands))
      {
        foreach (@playCommands)
        {
          @_ = split('\s*:\s*', $_);

          if ((2 != scalar(@_)) ||
              ($_[0] !~ /^[0-9]$/) ||
              ($_[1] !~ /^(?:stop|play|pause|next|previous)$/))
          {
            $fail = 1;
            last;
          }
        }
      }
      else
      {
        $fail = 1;
      }

      if ($fail)
      {
        return 'playCommands is required in format: <0-9>:stop,<0-9>:play,<0-9>:pause,<0-9>:next,<0-9>:previous';
      }
    }
    elsif ('maxNavigationItems' eq $attribute)
    {
      if (($value !~ /^\d+$/) || ($value < 1))
      {
        return 'maxNavigationItems must be a number greater than 0';
      }
    }
    elsif ('ttsWaitTimes' eq $attribute)
    {
      if (($value !~ /^(\d):(\d):(\d):(\d):(\d):(\d)$/) ||
          ($1 < 0) || ($2 < 0) || ($3 < 0) || ($4 < 0) || ($5 < 0) || ($6 < 0))
      {
        return 'ttsWaitTimes must be 6 numbers equal or greater than 0 joint by : (default: 0:2:0:2:0:0)';
      }
    }
    elsif ('compatibilityMode' eq $attribute)
    {
      if ((0 != $value) && ($hash->{INTERVAL} < 10))
      {
        return 'increase the update interval before switching to the compatibility mode (interval must be at least 10s)';
      }
    }
    elsif ('notifications' eq $attribute)
    {
      delete($hash->{helper}{notifications});
    }
    elsif ('streamPath' eq $attribute)
    {
      if ($value !~ /^\//)
      {
        return 'streamPath must start with /';
      }
      elsif ($value !~ /\/$/)
      {
        return 'streamPath must end with /';
      }
    }
  }

  return undef;
}


sub SIRD_Set($$@) {
  my ($hash, $name, @aa) = @_;
  my ($cmd, @args) = @aa;
  my $arg = $args[0];
  my $inputs = 'noArg';
  my $presets = '';
  my $presetsAll = '';
  my $input = ReadingsVal($name, 'input', '');
  my $inputReading = ReadingsVal($name, '.inputs', undef);
  my $volumeSteps = ReadingsVal($name, '.volumeSteps', 20);
  my $updateAfterSet = AttrVal($name, 'updateAfterSet', 1);

  if (defined($inputReading))
  {
    $inputs = '';

    while ($inputReading =~ /\d+:([^,]+),?/g)
    {
      my $inp = $1;
      my $presetReading = ReadingsVal($name, '.'.$inp.'presets', undef);

      $inputs .= ',' if ('' ne $inputs);
      $inputs .= $inp;

      if (defined($presetReading))
      {
        $presets = '';

        while ($presetReading =~ /\d+:([^,]+),?/g)
        {
          $presets .= ',' if ('' ne $presets);
          $presets .= $1;
        }

        $presetsAll .= ' ' if ('' ne $presetsAll);
        $presetsAll .= $inp.'preset:'.$presets;
      }
    }
  }

  if ('login' eq $cmd)
  {
    SIRD_SendRequest($hash, 'CREATE_SESSION', '', 0, 0, \&SIRD_ParseLogin);
  }
  elsif ($cmd =~ /^(?:on|off)$/)
  {
    SIRD_SendRequest($hash, 'SET', 'netRemote.sys.power', ('on' eq $cmd ? 1 : 0), 0, \&SIRD_ParsePower);
  }
  elsif ($cmd =~ /^(?:stop|play|pause|next|previous)$/)
  {
    my $playCommands = AttrVal($name, 'playCommands', '0:stop,1:play,2:pause,3:next,4:previous');

    if ($playCommands =~ /([0-9])\:$cmd/)
    {
      SIRD_SendRequest($hash, 'SET', 'netRemote.play.control', $1, 0, \&SIRD_ParsePlay);
    }
  }
  elsif ('input' eq $cmd)
  {
    if (defined($arg) && ($inputReading =~ /(\d+):$arg/))
    {
      SIRD_SendRequest($hash, 'SET', 'netRemote.sys.mode', $1, 0, \&SIRD_ParseInputs);
    }
  }
  elsif ($cmd =~ /preset$/)
  {
    my $presetReading = ReadingsVal($name, '.'.$cmd.'s', undef);

    if (defined($arg) && defined($presetReading) && ($presetReading =~ /(\d+):$arg/))
    {
      SIRD_SendRequest($hash, 'SET', 'netRemote.nav.action.selectPreset', $1, 0, \&SIRD_ParsePresets);
    }
  }
  elsif ('presetUp' eq $cmd)
  {
    my $lastPreset = ReadingsVal($name, '.lastPreset', undef);

    if (defined($lastPreset) && ($lastPreset < 6))
    {
      SIRD_SendRequest($hash, 'SET', 'netRemote.nav.action.selectPreset', $lastPreset + 1, 0, \&SIRD_ParsePresets);
    }
  }
  elsif ('presetDown' eq $cmd)
  {
    my $lastPreset = ReadingsVal($name, '.lastPreset', undef);

    if (defined($lastPreset) && ($lastPreset > 0))
    {
      SIRD_SendRequest($hash, 'SET', 'netRemote.nav.action.selectPreset', $lastPreset - 1, 0, \&SIRD_ParsePresets);
    }
  }
  elsif ('volume' eq $cmd)
  {
    SIRD_SendRequest($hash, 'SET', 'netRemote.sys.audio.volume', int($arg / (100 / $volumeSteps)), 0, \&SIRD_ParseVolume);
  }
  elsif ('volumeStraight' eq $cmd)
  {
    SIRD_SendRequest($hash, 'SET', 'netRemote.sys.audio.volume', int($arg), 0, \&SIRD_ParseVolume);
  }
  elsif ('volumeUp' eq $cmd)
  {
    my $volumeStraight = ReadingsVal($name, 'volumeStraight', undef);

    if (defined($volumeStraight) && ($volumeStraight < $volumeSteps))
    {
      SIRD_SendRequest($hash, 'SET', 'netRemote.sys.audio.volume', int($volumeStraight + 1), 0, \&SIRD_ParseVolume);
    }
  }
  elsif ('volumeDown' eq $cmd)
  {
    my $volumeStraight = ReadingsVal($name, 'volumeStraight', undef);

    if (defined($volumeStraight) && ($volumeStraight > 0))
    {
      SIRD_SendRequest($hash, 'SET', 'netRemote.sys.audio.volume', int($volumeStraight - 1), 0, \&SIRD_ParseVolume);
    }
  }
  elsif ('mute' eq $cmd)
  {
    $_ = 1 if ('on' eq $arg);
    $_ = 0 if ('off' eq $arg);
    $_ = ('on' eq ReadingsVal($name, 'mute', 'off') ? 0 : 1) if ('toggle' eq $arg);

    SIRD_SendRequest($hash, 'SET', 'netRemote.sys.audio.mute', $_, 0, \&SIRD_ParseMute);
  }
  elsif ('shuffle' eq $cmd)
  {
    SIRD_SendRequest($hash, 'SET', 'netRemote.play.shuffle', ('on' eq $arg ? 1 : 0), 0, \&SIRD_ParseShuffle);
  }
  elsif ('repeat' eq $cmd)
  {
    SIRD_SendRequest($hash, 'SET', 'netRemote.play.repeat', ('on' eq $arg ? 1 : 0), 0, \&SIRD_ParseRepeat);
  }
  elsif ('speak' eq $cmd)
  {
    my $text = '';
    my $ttsInput = AttrVal($name, 'ttsInput', 'dmr');

    eval { $text = encode_base64(join(' ', @args)) };

    if (('' ne $input) && ($ttsInput eq $input))
    {
      $ttsInput = '';
    }
    elsif ($inputReading =~ /(\d+):$ttsInput/)
    {
      $ttsInput = $1;
    }
    else
    {
      $ttsInput = '';
    }

    $input = $1 if ($inputReading =~ /(\d+):$input/);

    SIRD_StartSpeak($hash, $text, $input, $ttsInput, $volumeSteps);
  }
  elsif ('stream' eq $cmd)
  {
    my $streamInput = AttrVal($name, 'streamInput', 'dmr');
    my $streamPath = AttrVal($name, 'streamPath', '/opt/fhem/www/');
    my $streamPort = AttrVal($name, 'streamPort', 5000);

    if (('' ne $input) && ($streamInput eq $input))
    {
      $streamInput = '';
    }
    elsif ($inputReading =~ /(\d+):$streamInput/)
    {
      $streamInput = $1;
    }
    else
    {
      $streamInput = '';
    }

    $input = $1 if ($inputReading =~ /(\d+):$input/);

    if ($arg =~ /^https?:\/\//i)
    {
      SIRD_StartStream($hash, $arg, $input, $streamInput);
    }
    elsif (-e $streamPath.$arg)
    {
      my $socket = IO::Socket::INET->new(Proto    => 'udp',
                                         PeerAddr => '198.41.0.4',
                                         PeerPort => '53');
      my $ip = $socket->sockhost;

      SIRD_StartWebserver($hash, $streamPort, $streamPath, $arg);
      SIRD_StartStream($hash, 'http://'.$ip.':'.$streamPort.'/'.$arg, $input, $streamInput);
    }
    else
    {
      return 'Path not found! ('.$streamPath.$arg.')';
    }
  }
  elsif ('statusRequest' eq $cmd)
  {
    # do nothing here (readings already refreshed at the end)
  }
  # SetExtensions Commands
  elsif ($cmd =~ /^(?:on\-for\-timer|off\-for\-timer|on\-till|off\-till|on\-till\-overnight|off\till\-overnight|intervals|toggle)$/)
  {
    return SetExtensions($hash, 'on off', $name, $cmd, @args);
  }
  else
  {
    my $list = 'login:noArg on:noArg off:noArg mute:on,off,toggle shuffle:on,off repeat:on,off stop:noArg play:noArg pause:noArg '.
               'next:noArg previous:noArg presetUp:noArg presetDown:noArg volumeUp:noArg volumeDown:noArg '.
               'on-for-timer off-for-timer on-till off-till on-till-overnight off-till-overnight intervals toggle:noArg speak stream '.
               'volume:slider,0,1,100 volumeStraight:slider,0,1,'.$volumeSteps.' statusRequest:noArg input:'.$inputs.' '.$presetsAll;

    return 'Unknown argument '.$cmd.', choose one of '.$list;
  }

  SIRD_Update($hash) if (0 != $updateAfterSet);

  return undef;
}


sub SIRD_Get($$@) {
  my ($hash, $name, @aa) = @_;
  my ($cmd, @args) = @aa;

  if ('inputs' eq $cmd)
  {
    SIRD_SendRequest($hash, 'LIST_GET_NEXT', 'netRemote.sys.caps.validModes/-1', 65536, 0, \&SIRD_ParseInputs);
  }
  elsif ('presets' eq $cmd)
  {
    SIRD_SendRequest($hash, 'LIST_GET_NEXT', 'netRemote.nav.presets/-1', 20, 0, \&SIRD_ParsePresets);
  }
  elsif ('ls' eq $cmd)
  {
    my $ret;
    my ($index, $type) = @args;

    if (!defined($index) || !defined($type))
    {
      SIRD_StartNavigation($hash, -1, 0, $hash->{CL});
      return undef;
    }
    else
    {
      $type = 0 if ('dir' eq $type);
      $type = 1 if ('entry' eq $type);
      $type = 2 if ('back' eq $type);
      $type = 3 if ('next' eq $type);

      # back?
      if (2 == $type)
      {
        SIRD_SendRequest($hash, 'SET', 'netRemote.nav.action.navigate', -1, 0, \&SIRD_ParseNavigation, $hash->{CL});
      }
      # next?
      elsif (3 == $type)
      {
        SIRD_StartNavigation($hash, $index, 0, $hash->{CL});
      }
      # folder?
      elsif (0 == $type)
      {
        SIRD_SendRequest($hash, 'SET', 'netRemote.nav.action.navigate', $index, 0, \&SIRD_ParseNavigation, $hash->{CL});
      }
      # entry?
      elsif (1 == $type)
      {
        SIRD_SendRequest($hash, 'SET', 'netRemote.nav.action.selectItem', $index, 0, \&SIRD_ParseNavigation, $hash->{CL});
      }

      return undef;
    }
  }
  else
  {
    my $list = 'inputs:noArg presets:noArg ls';

    return 'Unknown argument '.$cmd.', choose one of '.$list;
  }

  return undef;
}


sub SIRD_CreateLink($$$$$)
{
  my ($type, $name, $itemname, $itemindex, $itemtype) = @_;

  if ($type eq 'FHEMWEB')
  {
    my $xcmd = 'cmd='.uri_escape('get '.$name.' ls '.$itemindex.' '.$itemtype);

    # single escaped ' if directly returned and double escaped ' if asyncOutput is used
    $xcmd = "FW_cmd(\\'$FW_ME$FW_subdir?XHR=1&$xcmd\\');\$(\\'#FW_okDialog\\').remove();";

    return '<a onClick="'.$xcmd.'" style="display:flex;align-items:center;cursor:pointer;">'.$itemname.'</a>';
  }
  else
  {
    $itemtype = 'dir' if (0 == $itemtype);
    $itemtype = 'entry' if (1 == $itemtype);
    $itemtype = 'back' if (2 == $itemtype);
    $itemtype = 'next' if (3 == $itemtype);

    return sprintf("%-6s %-6s %s\n", $itemindex, $itemtype, $itemname);
  }
}


sub SIRD_SetNextTimer($$)
{
  my ($hash, $timer) = @_;
  my $name = $hash->{NAME};
  my $interval = InternalVal($name, 'INTERVAL', 30);
  my $compatibilityMode = AttrVal($name, 'compatibilityMode', 1);

  Log3 $name, 5, $name.': SetNextTimer called';

  RemoveInternalTimer($hash);

  if (!defined($timer))
  {
    $interval = 10 if (($interval < 10) && (0 != $compatibilityMode));

    InternalTimer(gettimeofday() + $interval, 'SIRD_Update', $hash, 0);
  }
  else
  {
    InternalTimer(gettimeofday() + $timer, 'SIRD_Update', $hash, 0);
  }
}


sub SIRD_DeQueue($)
{
  my ($name) = @_;
  my $hash = $defs{$name};
  my $numEntries = (scalar(@SIRD_queue) < 5 ? scalar(@SIRD_queue) : 5);

  Log3 $name, 3, $name.': Queue full. Update interval MUST be increased!' if (scalar(@SIRD_queue) > 100);

  RemoveInternalTimer($name);
  InternalTimer(gettimeofday() + 1, 'SIRD_DeQueue', $name, 0) if (scalar(@SIRD_queue) > 0);

  # send max 5 requests each second
  for (my $i = 0; $i < $numEntries; $i++)
  {
    @_ = @{pop(@SIRD_queue)};

    SIRD_SendRequest($hash, $_[0], $_[1], $_[2], 0, $_[3]);
  }
}


sub SIRD_StartNavigation($$$;$)
{
  my ($hash, $index, $wait, $cl) = @_;
  my $name = $hash->{NAME};
  my $maxNavigationItems = AttrVal($name, 'maxNavigationItems', 100);
  my $ip = InternalVal($name, 'IP', undef);
  my $pin = InternalVal($name, 'PIN', '1234');

  if (exists($hash->{helper}{PID_NAVIGATION}))
  {
    Log3 $name, 3, $name.': Blocking call already running (navigation).';

    BlockingKill($hash->{helper}{PID_NAVIGATION}) if (defined($hash->{helper}{PID_NAVIGATION}));
  }

  $hash->{helper}{CL} = (defined($cl) ? $cl : $hash->{CL});

  $hash->{helper}{PID_NAVIGATION} = BlockingCall('SIRD_DoNavigation', $name.'|'.$ip.'|'.$pin.'|'.$index.'|'.$wait.'|'.$maxNavigationItems, 'SIRD_EndNavigation', 60, 'SIRD_AbortNavigation', $hash);
}


sub SIRD_DoNavigation(@)
{
  my ($string) = @_;
  my ($name, $ip, $pin, $index, $wait, $maxNavigationItems) = split("\\|", $string);
  my $data = '';
  my $nav = '<<BACK';
  my $numNav = $index;
  my $lastNumNav = $index;
  my $xml;
  my $retry;
  my $retryCounter = 0;

  Log3 $name, 5, $name.': Blocking call running to read navigation items.';

  do
  {
    $retry = 0;

    if (0 != $wait)
    {
      sleep($wait);
    }

    $data = GetFileFromURL('http://'.$ip.':80/fsapi/GET/netRemote.nav.numItems?pin='.$pin, 5, '', 1, 5);
    if ($data && ($data =~ /fsapiResponse/))
    {
      eval {$xml = xmlin($data, keeproot => 0);};

      if (!$@ && ('FS_OK' eq $xml->{status}))
      {
        $numNav = ($xml->{value}->{s32} >= 1 ? $xml->{value}->{s32} - 1 : 1);
      }
      else
      {
        $retry = 1;
      }
    }
    else
    {
      $retry = 1;
    }

    if (0 == $retry)
    {
      while (($lastNumNav < ($index + $maxNavigationItems)) && ($lastNumNav < $numNav))
      {
        $data = GetFileFromURL('http://'.$ip.':80/fsapi/LIST_GET_NEXT/netRemote.nav.list/'.$lastNumNav.'?pin='.$pin.'&maxItems=50', 10, '', 1, 5);
        if ($data && ($data =~ /fsapiResponse/))
        {
          Log3 $name, 5, $name.': data = '.$data;

          eval {$xml = xmlin($data, keeproot => 0);};

          if (!$@ && ('FS_OK' eq $xml->{status}))
          {
            my $result = '';

            foreach my $item (@{forcearray($xml->{item})})
            {
              if (exists($item->{key}) && exists($item->{field}) && (scalar(@{forcearray($item->{field})}) >= 1))
              {
                my $type = undef;
                my $name = undef;

                foreach my $field (@{forcearray($item->{field})})
                {
                  if (exists($field->{name}) && ('name' eq $field->{name}) && !ref($field->{c8_array}))
                  {
                    $_ = $field->{c8_array};
                    $_ =~ s/[^0-9a-zA-Z\.\-\_]+//g;

                    $name = $item->{key}.':'.$_;

                    $lastNumNav = $item->{key};
                  }

                  if (exists($field->{name}) && ('type' eq $field->{name}))
                  {
                    $type = $field->{u8};
                  }
                }

                if (defined($name) && defined($type))
                {
                  $result .= ',' if ('' ne $result);
                  $result .= $name.':'.$type;
                }
              }
            }

            if ('' ne $result)
            {
              Log3 $name, 5, $name.': result = '.$result;
              $nav .= $result;
            }
          }
          else
          {
            $lastNumNav = $numNav;
            $retry = 1;
          }
        }
        else
        {
          $lastNumNav = $numNav;
          $retry = 1;
        }
      }
    }

    $retryCounter++;
  } while ((1 == $retry) && ($retryCounter < 3));

  if ($lastNumNav < $numNav)
  {
    $nav .= 'NEXT>>';
  }

  return $name.'|'.$nav;
}


sub SIRD_EndNavigation($)
{
  my ($string) = @_;
  my ($name, $nav) = split("\\|", $string);
  my $hash = $defs{$name};
  my $ret;
  my $lastIndex = -1;

  if (defined($hash->{helper}{CL}) && $hash->{helper}{CL}{canAsyncOutput})
  {
    if ('FHEMWEB' eq $hash->{helper}{CL}{TYPE})
    {
      $ret = '<html><div class="container">';
      $ret .= '<h3 style="text-align: center;">Navigation</h3><hr>';
      $ret .= '<div class="list-group">';
    }
    else
    {
      $ret = "Navigation\n";
      $ret .= sprintf("%-6s %-6s %s\n", 'index', 'type', 'title');
    }

    $ret .= SIRD_CreateLink($hash->{helper}{CL}{TYPE}, $name, '&lt;&lt;BACK', -1, 2);

    while ($nav =~ /(\d+):([^:]+):(\d+),?/g)
    {
      $ret .= SIRD_CreateLink($hash->{helper}{CL}{TYPE}, $name, $2, $1, $3);

      $lastIndex = $1;
    }

    if ($nav =~ /NEXT\>\>$/)
    {
      $ret .= SIRD_CreateLink($hash->{helper}{CL}{TYPE}, $name, 'NEXT&gt;&gt;', $lastIndex, 3);
    }

    if ('FHEMWEB' eq $hash->{helper}{CL}{TYPE})
    {
      $ret .= '</div></div></html>';
    }

    asyncOutput($hash->{helper}{CL}, $ret);
  }
  else
  {
    Log3 $name, 3, $name.': asyncOutput not supported!';
  }

  Log3 $name, 5, $name.': Blocking call finished to read navigation items.';

  delete($hash->{helper}{PID_NAVIGATION});
}


sub SIRD_AbortNavigation($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  delete($hash->{helper}{PID_NAVIGATION});

  Log3 $name, 3, $name.': Blocking call aborted (navigation).';
}


sub SIRD_StartSpeak($$$$$)
{
  my ($hash, $text, $input, $ttsInput, $volumeSteps) = @_;
  my $name = $hash->{NAME};
  my $ip = InternalVal($name, 'IP', undef);
  my $pin = InternalVal($name, 'PIN', '1234');
  my $language = AttrVal($name, 'ttsLanguage', 'de');
  # PowerOn,LoadStream,SetVolumeTTS,SetVolumeNormal,SetInput,PowerOff
  my $ttsWaitTimes = AttrVal($name, 'ttsWaitTimes', '0:2:0:2:0:0');
  my $power = ReadingsVal($name, 'power', 'on');
  my $ttsVolume = AttrVal($name, 'ttsVolume', 25);
  my $volume = ReadingsVal($name, 'volume', 25);
  my $volumeStraight = ReadingsVal($name, 'volumeStraight', int($volume / (100 / $volumeSteps)));

  if (exists($hash->{helper}{PID_SPEAK}))
  {
    Log3 $name, 3, $name.': Blocking call already running (speak).';

    BlockingKill($hash->{helper}{PID_SPEAK}) if (defined($hash->{helper}{PID_SPEAK}));
  }

  if (length($text) > 100)
  {
    Log3 $name, 3, $name.': Too many chars for speak (more than 100).';
  }

  $hash->{helper}{suspendUpdate} = 1;
  @SIRD_queue = ();
  $hash->{helper}{PID_SPEAK} = BlockingCall('SIRD_DoSpeak', $name.'|'.$ip.'|'.$pin.'|'.$text.'|'.$language.'|'.$input.'|'.$ttsInput.'|'.$volume.'|'.$ttsVolume.'|'.$volumeStraight.'|'.$volumeSteps.'|'.$power.'|'.$ttsWaitTimes, 'SIRD_EndSpeak', 120, 'SIRD_AbortSpeak', $hash);
}


sub SIRD_DoSpeak(@)
{
  my ($string) = @_;
  my ($name, $ip, $pin, $text, $language, $input, $ttsInput, $volume, $ttsVolume, $volumeStraight, $volumeSteps, $power, $ttsWaitTimes) = split("\\|", $string);
  my ($ttsWait1, $ttsWait2, $ttsWait3, $ttsWait4, $ttsWait5, $ttsWait6) = split("\\:", $ttsWaitTimes);
  my $param;
  my $err;
  my $data;
  my $xml;
  my $retryCounter;

  eval { $text = decode_base64($text) };

  my $uri_text = uri_escape($text);
  my $url = 'http://translate.google.com/translate_tts?ie=UTF-8&tl='.$language.'&client=tw-ob&q='.$uri_text;

  $url =~ s/\&/\&amp\;/g;

  Log3 $name, 5, $name.': Blocking call running to speak.';

  if ('' ne $ttsInput)
  {
    Log3 $name, 5, $name.': start switch to dmr.';

    $data = GetFileFromURL('http://'.$ip.':80/fsapi/SET/netRemote.sys.mode?pin='.$pin.'&value='.$ttsInput, 5, '', 1, 5);
  }

  if ('off' eq $power)
  {
    Log3 $name, 5, $name.': start power on.';

    GetFileFromURL('http://'.$ip.':80/fsapi/SET/netRemote.sys.power?pin='.$pin.'&value=1', 5, '', 1, 5);
    if ($data && ($data =~ /fsapiResponse/))
    {
      eval {$xml = xmlin($data, keeproot => 0);};

      if (!$@ && ('FS_OK' eq $xml->{status}))
      {
        $retryCounter = 0;

        do
        {
          $data = GetFileFromURL('http://'.$ip.':80/fsapi/GET/netRemote.sys.power?pin='.$pin, 5, '', 1, 5);
          if ($data && ($data =~ /fsapiResponse/))
          {
            eval {$xml = xmlin($data, keeproot => 0);};

            if (!$@ && ('FS_OK' eq $xml->{status}))
            {
              if (1 == $xml->{value}->{u8})
              {
                Log3 $name, 5, $name.': power on successfully completed. ('.$retryCounter.')';

                $retryCounter = 10;
              }
            }
          }

          $retryCounter++;
        } while ($retryCounter < 10);
      }
    }

    sleep($ttsWait1) if ($ttsWait1 > 0);
  }

  $param = {
              url        => 'http://'.$ip.':8080/AVTransport/control',
              timeout    => 10,
              header     => { 'Content-Type' => 'text/xml; charset=utf-8',
                              'SOAPAction' => '"urn:schemas-upnp-org:service:AVTransport:1#Stop"' },
              data       => '<?xml version="1.0" encoding="utf-8"?>'.
                            '<s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">'.
                            '<s:Body><u:Stop xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">'.
                            '<InstanceID>0</InstanceID></u:Stop></s:Body></s:Envelope>',
              #loglevel   => 3,
              method     => 'POST'
           };

  ($err, $data) = HttpUtils_BlockingGet($param);

  if ('' ne $err)
  {
    Log3 $name, 3, $name.': Something went wrong by setting Stop. ('.$err.')';
  }
  else
  {
    Log3 $name, 5, $name.': '.Dumper($data);
  }

  $param = {
              url        => 'http://'.$ip.':8080/AVTransport/control',
              timeout    => 10,
              header     => { 'Content-Type' => 'text/xml; charset=utf-8',
                              'SOAPAction' => '"urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI"' },
              data       => '<?xml version="1.0" encoding="utf-8"?>'.
                            '<s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">'.
                            '<s:Body><u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">'.
                            '<InstanceID>0</InstanceID><CurrentURI>'.$url.'</CurrentURI><CurrentURIMetaData>'.
                            '</CurrentURIMetaData></u:SetAVTransportURI></s:Body></s:Envelope>',
              #loglevel   => 3,
              method     => 'POST'
            };

  ($err, $data) = HttpUtils_BlockingGet($param);

  if ('' ne $err)
  {
    Log3 $name, 3, $name.': Something went wrong by setting AVTransportURI. ('.$err.')';

    return $name;
  }
  else
  {
    Log3 $name, 5, $name.': '.Dumper($param);
    Log3 $name, 5, $name.': '.Dumper($data);
  }

  sleep($ttsWait2) if ($ttsWait2 > 0);

  if ($volume != $ttsVolume)
  {
    GetFileFromURL('http://'.$ip.':80/fsapi/SET/netRemote.sys.audio.volume?pin='.$pin.'&value='.int($ttsVolume / (100 / $volumeSteps)), 5, '', 1, 5);

    sleep($ttsWait3) if ($ttsWait3 > 0);
  }

  $param = {
              url        => 'http://'.$ip.':8080/AVTransport/control',
              timeout    => 10,
              header     => { 'Content-Type' => 'text/xml; charset=utf-8',
                              'SOAPAction' => '"urn:schemas-upnp-org:service:AVTransport:1#Play"' },
              data       => '<?xml version="1.0" encoding="utf-8"?>'.
                            '<s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">'.
                            '<s:Body><u:Play xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">'.
                            '<InstanceID>0</InstanceID><Speed>1</Speed></u:Play></s:Body></s:Envelope>',
              #loglevel   => 3,
              method     => 'POST'
           };

  ($err, $data) = HttpUtils_BlockingGet($param);

  if ('' ne $err)
  {
    Log3 $name, 3, $name.': Something went wrong by setting Play. ('.$err.')';
  }
  else
  {
    Log3 $name, 5, $name.': '.Dumper($data);
  }

  sleep(1);
  $retryCounter = 0;
  do
  {
    sleep(1);

    $data = GetFileFromURL('http://'.$ip.':80/fsapi/GET/netRemote.play.status?pin='.$pin, 5, '', 1, 5);
    if ($data && ($data =~ /fsapiResponse/))
    {
      eval {$xml = xmlin($data, keeproot => 0);};

      if (!$@ && ('FS_OK' eq $xml->{status}))
      {
        #Log3 $name, 3, $name.': '.Dumper($xml);

        if (0 == $xml->{value}->{u8})
        {
          Log3 $name, 5, $name.': speak command completed. ('.$retryCounter.')';

          $retryCounter = 120;
        }
      }
    }

    $retryCounter++;
  } while ($retryCounter < 120);

  if ($volume != $ttsVolume)
  {
    GetFileFromURL('http://'.$ip.':80/fsapi/SET/netRemote.sys.audio.volume?pin='.$pin.'&value='.int($volumeStraight), 5, '', 1, 5);

    sleep($ttsWait4) if ($ttsWait4 > 0);
  }

  if ('' ne $ttsInput)
  {
    GetFileFromURL('http://'.$ip.':80/fsapi/SET/netRemote.sys.mode?pin='.$pin.'&value='.$input, 5, '', 1, 5);

    sleep($ttsWait5) if ($ttsWait5 > 0);
  }

  if ('off' eq $power)
  {
    GetFileFromURL('http://'.$ip.':80/fsapi/SET/netRemote.sys.power?pin='.$pin.'&value=0', 5, '', 1, 5);

    sleep($ttsWait6) if ($ttsWait6 > 0);
  }

  return $name;
}


sub SIRD_EndSpeak($)
{
  my ($name) = @_;
  my $hash = $defs{$name};

  Log3 $name, 5, $name.': Blocking call finished to speak.';

  $hash->{helper}{suspendUpdate} = 0;

  delete($hash->{helper}{PID_SPEAK});
}


sub SIRD_AbortSpeak($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  $hash->{helper}{suspendUpdate} = 0;

  delete($hash->{helper}{PID_SPEAK});

  Log3 $name, 3, $name.': Blocking call aborted (speak).';
}


sub SIRD_StartStream($$$$)
{
  my ($hash, $stream, $input, $streamInput) = @_;
  my $name = $hash->{NAME};
  my $ip = InternalVal($name, 'IP', undef);
  my $pin = InternalVal($name, 'PIN', '1234');
  # PowerOn,LoadStream,SetInput,PowerOff
  my $streamWaitTimes = AttrVal($name, 'streamWaitTimes', '0:2:0:0');
  my $power = ReadingsVal($name, 'power', 'on');

  if (exists($hash->{helper}{PID_STREAM}))
  {
    Log3 $name, 3, $name.': Blocking call already running (stream).';

    BlockingKill($hash->{helper}{PID_STREAM}) if (defined($hash->{helper}{PID_STREAM}));
  }

  $hash->{helper}{PID_STREAM} = BlockingCall('SIRD_DoStream', $name.'|'.$ip.'|'.$pin.'|'.$stream.'|'.$input.'|'.$streamInput.'|'.$power.'|'.$streamWaitTimes, 'SIRD_EndStream');
}


sub SIRD_DoStream(@)
{
  my ($string) = @_;
  my ($name, $ip, $pin, $stream, $input, $streamInput, $power, $streamWaitTimes) = split("\\|", $string);
  my ($streamWait1, $streamWait2, $streamWait3, $streamWait4) = split("\\:", $streamWaitTimes);
  my $param;
  my $err;
  my $data;
  my $xml;
  my $retryCounter;

  Log3 $name, 5, $name.': Blocking call running to stream.';

  if ('' ne $streamInput)
  {
    Log3 $name, 5, $name.': start switch to dmr.';

    $data = GetFileFromURL('http://'.$ip.':80/fsapi/SET/netRemote.sys.mode?pin='.$pin.'&value='.$streamInput, 5, '', 1, 5);
  }

  if ('off' eq $power)
  {
    Log3 $name, 5, $name.': start power on.';

    GetFileFromURL('http://'.$ip.':80/fsapi/SET/netRemote.sys.power?pin='.$pin.'&value=1', 5, '', 1, 5);
    if ($data && ($data =~ /fsapiResponse/))
    {
      eval {$xml = xmlin($data, keeproot => 0);};

      if (!$@ && ('FS_OK' eq $xml->{status}))
      {
        $retryCounter = 0;

        do
        {
          $data = GetFileFromURL('http://'.$ip.':80/fsapi/GET/netRemote.sys.power?pin='.$pin, 5, '', 1, 5);
          if ($data && ($data =~ /fsapiResponse/))
          {
            eval {$xml = xmlin($data, keeproot => 0);};

            if (!$@ && ('FS_OK' eq $xml->{status}))
            {
              if (1 == $xml->{value}->{u8})
              {
                Log3 $name, 5, $name.': power on successfully completed. ('.$retryCounter.')';

                $retryCounter = 10;
              }
            }
          }

          $retryCounter++;
        } while ($retryCounter < 10);
      }
    }

    sleep($streamWait1) if ($streamWait1 > 0);
  }

  $param = {
              url        => 'http://'.$ip.':8080/AVTransport/control',
              timeout    => 10,
              header     => { 'Content-Type' => 'text/xml; charset=utf-8',
                              'SOAPAction' => '"urn:schemas-upnp-org:service:AVTransport:1#Stop"' },
              data       => '<?xml version="1.0" encoding="utf-8"?>'.
                            '<s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">'.
                            '<s:Body><u:Stop xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">'.
                            '<InstanceID>0</InstanceID></u:Stop></s:Body></s:Envelope>',
              #loglevel   => 3,
              method     => 'POST'
           };

  ($err, $data) = HttpUtils_BlockingGet($param);

  if ('' ne $err)
  {
    Log3 $name, 3, $name.': Something went wrong by setting Stop. ('.$err.')';
  }
  else
  {
    Log3 $name, 5, $name.': '.Dumper($data);
  }

  $param = {
              url        => 'http://'.$ip.':8080/AVTransport/control',
              timeout    => 10,
              header     => { 'Content-Type' => 'text/xml; charset=utf-8',
                              'SOAPAction' => '"urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI"' },
              data       => '<?xml version="1.0" encoding="utf-8"?>'.
                            '<s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">'.
                            '<s:Body><u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">'.
                            '<InstanceID>0</InstanceID><CurrentURI>'.$stream.'</CurrentURI><CurrentURIMetaData>'.
                            '</CurrentURIMetaData></u:SetAVTransportURI></s:Body></s:Envelope>',
              #loglevel   => 3,
              method     => 'POST'
            };

  ($err, $data) = HttpUtils_BlockingGet($param);

  if ('' ne $err)
  {
    Log3 $name, 3, $name.': Something went wrong by setting AVTransportURI. ('.$err.')';

    return $name;
  }
  else
  {
    Log3 $name, 5, $name.': '.Dumper($param);
    Log3 $name, 5, $name.': '.Dumper($data);
  }

  sleep($streamWait2) if ($streamWait2 > 0);

  $param = {
              url        => 'http://'.$ip.':8080/AVTransport/control',
              timeout    => 10,
              header     => { 'Content-Type' => 'text/xml; charset=utf-8',
                              'SOAPAction' => '"urn:schemas-upnp-org:service:AVTransport:1#Play"' },
              data       => '<?xml version="1.0" encoding="utf-8"?>'.
                            '<s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">'.
                            '<s:Body><u:Play xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">'.
                            '<InstanceID>0</InstanceID><Speed>1</Speed></u:Play></s:Body></s:Envelope>',
              #loglevel   => 3,
              method     => 'POST'
           };

  ($err, $data) = HttpUtils_BlockingGet($param);

  if ('' ne $err)
  {
    Log3 $name, 3, $name.': Something went wrong by setting Play. ('.$err.')';
  }
  else
  {
    Log3 $name, 5, $name.': '.Dumper($data);
  }

  sleep(1);
  $retryCounter = 0;
  do
  {
    sleep(1);

    $data = GetFileFromURL('http://'.$ip.':80/fsapi/GET/netRemote.play.status?pin='.$pin, 5, '', 1, 5);
    if ($data && ($data =~ /fsapiResponse/))
    {
      eval {$xml = xmlin($data, keeproot => 0);};

      if (!$@ && ('FS_OK' eq $xml->{status}))
      {
        #Log3 $name, 3, $name.': '.Dumper($xml);

        if (0 == $xml->{value}->{u8})
        {
          Log3 $name, 5, $name.': stream command completed.';

          $retryCounter = 1;
        }
      }
    }
  } while (0 == $retryCounter);

  if ('' ne $streamInput)
  {
    GetFileFromURL('http://'.$ip.':80/fsapi/SET/netRemote.sys.mode?pin='.$pin.'&value='.$input, 5, '', 1, 5);

    sleep($streamWait3) if ($streamWait3 > 0);
  }

  if ('off' eq $power)
  {
    GetFileFromURL('http://'.$ip.':80/fsapi/SET/netRemote.sys.power?pin='.$pin.'&value=0', 5, '', 1, 5);

    sleep($streamWait4) if ($streamWait4 > 0);
  }

  return $name;
}


sub SIRD_EndStream($)
{
  my ($name) = @_;
  my $hash = $defs{$name};

  BlockingKill($hash->{helper}{PID_WEBSERVER}) if (defined($hash->{helper}{PID_WEBSERVER}));
  delete($hash->{helper}{PID_WEBSERVER});
  delete($hash->{helper}{PID_STREAM});

  Log3 $name, 5, $name.': Blocking call finished to stream.';
}


sub SIRD_AbortStream($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  BlockingKill($hash->{helper}{PID_WEBSERVER}) if (defined($hash->{helper}{PID_WEBSERVER}));
  delete($hash->{helper}{PID_WEBSERVER});
  delete($hash->{helper}{PID_STREAM});

  Log3 $name, 3, $name.': Blocking call aborted (stream).';
}


sub SIRD_StartWebserver($$$$)
{
  my ($hash, $port, $path, $file) = @_;
  my $name = $hash->{NAME};

  if (exists($hash->{helper}{PID_WEBSERVER}))
  {
    Log3 $name, 3, $name.': Blocking call already running (webserver).';

    BlockingKill($hash->{helper}{PID_WEBSERVER}) if (defined($hash->{helper}{PID_WEBSERVER}));
  }

  $hash->{helper}{PID_WEBSERVER} = BlockingCall('SIRD_DoWebserver', $name.'|'.$port.'|'.$path.'|'.$file);
}


sub SIRD_DoWebserver(@)
{
  my ($string) = @_;
  my ($name, $port, $path, $file) = split("\\|", $string);

  Log3 $name, 5, $name.': Blocking call running: webserver.';

  my $d = HTTP::Daemon->new(LocalPort => $port, ReuseAddr => 1, Timeout => 300) or return $name;

  while (my $c = $d->accept)
  {
    while (my $r = $c->get_request)
    {
      Log3 $name, 3, $name.': Webserver request: '.Dumper($r);

      if ('HEAD' eq $r->method)
      {
        $c->send_header('Content-Type', 'audio/mpeg');
        $c->send_response(200, 'OK');
      }

      if ('GET' eq $r->method)
      {
        $c->send_file_response($path.$file);

        Log3 $name, 3, $name.': Webserver send: '.$path.$file;
      }
    }

    $c->close;

    Log3 $name, 3, $name.': Webserver closed';
  }

  return $name;
}


sub SIRD_Update($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $notifications = AttrVal($name, 'notifications', 0);

  return undef if (IsDisabled($name));

  SIRD_SetNextTimer($hash, undef);

  return undef if ($hash->{helper}{suspendUpdate});

  if (0 != $notifications)
  {
    if (!exists($hash->{helper}{notifications}))
    {
      # start notifications
      SIRD_SendRequest($hash, 'GET_NOTIFIES', '', 0, 1, \&SIRD_ParseNotifies);

      $hash->{helper}{notifications} = 1;

      Log3 $name, 5, $name.': Notifications started';
    }
  }
  else
  {
    delete($hash->{helper}{notifications});
  }

  SIRD_SendRequest($hash, 'GET', 'netRemote.sys.power', 0, 0, \&SIRD_ParsePower);

  if (1 == AttrVal($name, 'compatibilityMode', 1))
  {
    unshift(@SIRD_queue, ['GET', 'netRemote.nav.state', 0, \&SIRD_ParseGeneral]);
    unshift(@SIRD_queue, ['GET', 'netRemote.nav.status', 0, \&SIRD_ParseGeneral]);
    unshift(@SIRD_queue, ['GET', 'netRemote.sys.caps.volumeSteps', 0, \&SIRD_ParseGeneral]);
    unshift(@SIRD_queue, ['GET', 'netRemote.nav.numItems', 0, \&SIRD_ParseGeneral]);

    # run dequeue
    SIRD_DeQueue($name);

    unshift(@SIRD_queue, ['GET', 'netRemote.sys.mode', 0, \&SIRD_ParseGeneral]);
    unshift(@SIRD_queue, ['GET', 'netRemote.sys.info.version', 0, \&SIRD_ParseGeneral]);
    unshift(@SIRD_queue, ['GET', 'netRemote.sys.info.friendlyName', 0, \&SIRD_ParseGeneral]);
    unshift(@SIRD_queue, ['GET', 'netRemote.sys.audio.volume', 0, \&SIRD_ParseGeneral]);
    unshift(@SIRD_queue, ['GET', 'netRemote.sys.net.wlan.rssi', 0, \&SIRD_ParseGeneral]);
  }
  else
  {
    SIRD_SendRequest($hash, 'GET_MULTIPLE', 'node=netRemote.nav.state&'.
                                            'node=netRemote.nav.status&'.
                                            'node=netRemote.sys.caps.volumeSteps&'.
                                            'node=netRemote.nav.numItems&'.
                                            'node=netRemote.sys.mode&'.
                                            'node=netRemote.sys.info.version&'.
                                            'node=netRemote.sys.info.friendlyName&'.
                                            'node=netRemote.sys.audio.volume&'.
                                            'node=netRemote.sys.net.wlan.rssi&', 0, 0, \&SIRD_ParseMultiple);
  }

  if (!defined(ReadingsVal($name, '.inputs', undef)) || ('' eq ReadingsVal($name, '.inputs', '')))
  {
    SIRD_SendRequest($hash, 'LIST_GET_NEXT', 'netRemote.sys.caps.validModes/-1', 65536, 0, \&SIRD_ParseInputs);
  }
  SIRD_SendRequest($hash, 'LIST_GET_NEXT', 'netRemote.nav.presets/-1', 20, 0, \&SIRD_ParsePresets);

  if ('on' eq ReadingsVal($name, 'power', 'unknown'))
  {
    if (1 == AttrVal($name, 'compatibilityMode', 1))
    {
      unshift(@SIRD_queue, ['GET', 'netRemote.play.info.description', 0, \&SIRD_ParseGeneral]);
      unshift(@SIRD_queue, ['GET', 'netRemote.play.info.albumDescription', 0, \&SIRD_ParseGeneral]);
      unshift(@SIRD_queue, ['GET', 'netRemote.play.info.artistDescription', 0, \&SIRD_ParseGeneral]);
      unshift(@SIRD_queue, ['GET', 'netRemote.play.info.duration', 0, \&SIRD_ParseGeneral]);
      unshift(@SIRD_queue, ['GET', 'netRemote.play.info.artist', 0, \&SIRD_ParseGeneral]);
      unshift(@SIRD_queue, ['GET', 'netRemote.play.info.album', 0, \&SIRD_ParseGeneral]);
      unshift(@SIRD_queue, ['GET', 'netRemote.play.info.name', 0, \&SIRD_ParseGeneral]);
      unshift(@SIRD_queue, ['GET', 'netRemote.play.info.graphicUri', 0, \&SIRD_ParseGeneral]);
      unshift(@SIRD_queue, ['GET', 'netRemote.play.info.text', 0, \&SIRD_ParseGeneral]);
      unshift(@SIRD_queue, ['GET', 'netRemote.nav.numItems', 0, \&SIRD_ParseGeneral]);
      unshift(@SIRD_queue, ['GET', 'netRemote.play.status', 0, \&SIRD_ParseGeneral]);
      unshift(@SIRD_queue, ['GET', 'netRemote.play.frequency', 0, \&SIRD_ParseGeneral]);
      unshift(@SIRD_queue, ['GET', 'netRemote.play.errorStr', 0, \&SIRD_ParseGeneral]);
      unshift(@SIRD_queue, ['GET', 'netRemote.play.position', 0, \&SIRD_ParseGeneral]);
      unshift(@SIRD_queue, ['GET', 'netRemote.play.repeat', 0, \&SIRD_ParseGeneral]);
      unshift(@SIRD_queue, ['GET', 'netRemote.play.shuffle', 0, \&SIRD_ParseGeneral]);
      unshift(@SIRD_queue, ['GET', 'netRemote.play.signalStrength', 0, \&SIRD_ParseGeneral]);
      unshift(@SIRD_queue, ['GET', 'netRemote.sys.audio.mute', 0, \&SIRD_ParseGeneral]);
    }
    else
    {
      SIRD_SendRequest($hash, 'GET_MULTIPLE', 'node=netRemote.play.info.name&'.
                                              'node=netRemote.play.info.description&'.
                                              'node=netRemote.play.info.albumDescription&'.
                                              'node=netRemote.play.info.artistDescription&'.
                                              'node=netRemote.play.info.duration&'.
                                              'node=netRemote.play.info.artist&'.
                                              'node=netRemote.play.info.album&'.
                                              'node=netRemote.play.info.graphicUri&'.
                                              'node=netRemote.play.info.text&'.
                                              'node=netRemote.nav.numItems&', 0, 0, \&SIRD_ParseMultiple);

      SIRD_SendRequest($hash, 'GET_MULTIPLE', 'node=netRemote.sys.mode&'.
                                              'node=netRemote.play.status&'.
                                              'node=netRemote.play.frequency&'.
                                              'node=netRemote.play.errorStr&'.
                                              'node=netRemote.play.position&'.
                                              'node=netRemote.play.repeat&'.
                                              'node=netRemote.play.shuffle&'.
                                              'node=netRemote.play.signalStrength&'.
                                              'node=netRemote.sys.audio.mute&', 0, 0, \&SIRD_ParseMultiple);

      #SIRD_SendRequest($hash, 'GET_MULTIPLE', 'node=netRemote.multiroom.group.name&'.
      #                                        'node=netRemote.multiroom.group.id&'.
      #                                        'node=netRemote.multiroom.group.state&'.
      #                                        'node=netRemote.multiroom.device.serverStatus&'.
      #                                        'node=netRemote.multiroom.caps.maxClients&', 0, 0, \&SIRD_ParseMultiple);

      #SIRD_SendRequest($hash, 'GET_MULTIPLE', 'node=netRemote.multichannel.system.name&'.
      #                                        'node=netRemote.multichannel.system.id&'.
      #                                        'node=netRemote.multichannel.system.state&', 0, 0, \&SIRD_ParseMultiple);
    }
  }
  else
  {
    readingsBeginUpdate($hash);
    SIRD_ClearReadings($hash);
    readingsEndUpdate($hash, 1);
  }

  if ('' eq ReadingsVal($name, 'power', ''))
  {
    readingsSingleUpdate($hash, 'state', 'absent', 1);
  }
  else
  {
    readingsSingleUpdate($hash, 'state', ReadingsVal($name, 'power', ''), 1);
  }
}


sub SIRD_ClearReadings($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  readingsBulkUpdateIfChanged($hash, 'currentTitle', '');
  readingsBulkUpdateIfChanged($hash, 'description', '');
  readingsBulkUpdateIfChanged($hash, 'currentAlbumDescription', '');
  readingsBulkUpdateIfChanged($hash, 'currentArtistDescription', '');
  readingsBulkUpdateIfChanged($hash, 'duration', '');
  readingsBulkUpdateIfChanged($hash, 'currentArtist', '');
  readingsBulkUpdateIfChanged($hash, 'currentAlbum', '');
  readingsBulkUpdateIfChanged($hash, 'graphicUri', '');
  readingsBulkUpdateIfChanged($hash, 'infoText', '');
  readingsBulkUpdateIfChanged($hash, 'playStatus', '');
  readingsBulkUpdateIfChanged($hash, 'errorStr', '');
  readingsBulkUpdateIfChanged($hash, 'position', '');
  readingsBulkUpdateIfChanged($hash, 'repeat', '');
  readingsBulkUpdateIfChanged($hash, 'shuffle', '');
  readingsBulkUpdateIfChanged($hash, 'mute', '');
  readingsBulkUpdateIfChanged($hash, 'preset', '');
  readingsBulkUpdateIfChanged($hash, 'frequency', '');
  readingsBulkUpdateIfChanged($hash, 'signalStrength', '');
}


sub SIRD_SetReadings($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $reading;

  if (('nav.state' eq $_->{node}) && (0 == $_->{value}->{u8}))
  {
    # enable navigation if needed!!!
    SIRD_SendRequest($hash, 'SET', 'netRemote.nav.state', 1, 0, \&SIRD_ParseNavState);
  }
  elsif ('sys.caps.volumeSteps' eq $_->{node})
  {
    readingsBulkUpdateIfChanged($hash, '.volumeSteps', ($_->{value}->{u8} > 20 && $_->{value}->{u8} < 99 ? $_->{value}->{u8} - 1 : 20));
  }
  elsif ('nav.numItems' eq $_->{node})
  {
    readingsBulkUpdateIfChanged($hash, '.numNav', $_->{value}->{s32} - 1);
  }
  elsif ('sys.mode' eq $_->{node})
  {
    my $inputReading = ReadingsVal($name, '.inputs', '');

    if ($inputReading =~ /$_->{value}->{u32}:(.*?)(?:,|$)/)
    {
      readingsBulkUpdateIfChanged($hash, 'input', $1);
    }
  }
  elsif ('sys.info.version' eq $_->{node})
  {
    $reading = encode_utf8(!ref($_->{value}->{c8_array}) ? $_->{value}->{c8_array} : '');

    readingsBulkUpdateIfChanged($hash, 'version', $reading);
  }
  elsif ('sys.info.friendlyName' eq $_->{node})
  {
    $reading = encode_utf8(!ref($_->{value}->{c8_array}) ? $_->{value}->{c8_array} : '');

    readingsBulkUpdateIfChanged($hash, 'friendlyName', $reading);
  }
  elsif ('sys.audio.volume' eq $_->{node})
  {
    my $volumeSteps = ReadingsVal($name, '.volumeSteps', 20);

    readingsBulkUpdateIfChanged($hash, 'volume', int($_->{value}->{u8} * (100 / $volumeSteps)));
    readingsBulkUpdateIfChanged($hash, 'volumeStraight', int($_->{value}->{u8}));
  }
  elsif ('sys.net.wlan.rssi' eq $_->{node})
  {
    readingsBulkUpdateIfChanged($hash, 'rssi', $_->{value}->{u8});
  }
  elsif ('play.info.name' eq $_->{node})
  {
    $reading = encode_utf8(!ref($_->{value}->{c8_array}) ? $_->{value}->{c8_array} : '');

    readingsBulkUpdateIfChanged($hash, 'currentTitle', $reading);
  }
  elsif ('play.info.duration' eq $_->{node})
  {
    readingsBulkUpdateIfChanged($hash, 'duration', $_->{value}->{u32});
  }
  elsif ('play.signalStrength' eq $_->{node})
  {
    readingsBulkUpdateIfChanged($hash, 'signalStrength', $_->{value}->{u8});
  }
  elsif ('play.info.graphicUri' eq $_->{node})
  {
    $reading = encode_utf8(!ref($_->{value}->{c8_array}) ? $_->{value}->{c8_array} : '');

    readingsBulkUpdateIfChanged($hash, 'graphicUri', $reading);
  }
  elsif ('play.info.text' eq $_->{node})
  {
    $reading = encode_utf8(!ref($_->{value}->{c8_array}) ? $_->{value}->{c8_array} : '');

    readingsBulkUpdateIfChanged($hash, 'infoText', $reading);
  }
  elsif ('play.status' eq $_->{node})
  {
    my @result = ('idle', 'buffering', 'playing', 'paused', 'rebuffering', 'error', 'stopped');
    $reading = ($_->{value}->{u8} < 7 ? $result[$_->{value}->{u8}] : 'unknown');

    readingsBulkUpdateIfChanged($hash, 'playStatus', $reading);
  }
  elsif ('play.position' eq $_->{node})
  {
    my $minutes = $_->{value}->{u32} / 60000;
    my $seconds = ($_->{value}->{u32} / 1000) - (($_->{value}->{u32} / 60000) * 60);
    $reading = sprintf("%d:%02d", $minutes, $seconds);

    readingsBulkUpdateIfChanged($hash, 'position', $reading);
  }
  elsif ('play.repeat' eq $_->{node})
  {
    $reading = (1 == $_->{value}->{u8} ? 'on' : 'off');

    readingsBulkUpdateIfChanged($hash, 'repeat', $reading);
  }
  elsif ('play.shuffle' eq $_->{node})
  {
    $reading = (1 == $_->{value}->{u8} ? 'on' : 'off');

    readingsBulkUpdateIfChanged($hash, 'shuffle', $reading);
  }
  elsif ('play.frequency' eq $_->{node})
  {
    if ($_->{value}->{u32} < 200000)
    {
      readingsBulkUpdateIfChanged($hash, 'frequency', sprintf("%.2f", $_->{value}->{u32} / 1000));
    }
    else
    {
      readingsBulkUpdateIfChanged($hash, 'frequency', '');
    }
  }
  elsif ('sys.audio.mute' eq $_->{node})
  {
    $reading = (1 == $_->{value}->{u8} ? 'on' : 'off');

    readingsBulkUpdateIfChanged($hash, 'mute', $reading);
  }
  elsif ('play.info.artist' eq $_->{node})
  {
    $reading = encode_utf8(!ref($_->{value}->{c8_array}) ? $_->{value}->{c8_array} : '');

    readingsBulkUpdateIfChanged($hash, 'currentArtist', $reading);
  }
  elsif ('play.info.album' eq $_->{node})
  {
    $reading = encode_utf8(!ref($_->{value}->{c8_array}) ? $_->{value}->{c8_array} : '');

    readingsBulkUpdateIfChanged($hash, 'currentAlbum', $reading);
  }
  elsif ('play.info.albumDescription' eq $_->{node})
  {
    $reading = encode_utf8(!ref($_->{value}->{c8_array}) ? $_->{value}->{c8_array} : '');

    readingsBulkUpdateIfChanged($hash, 'currentAlbumDescription', $reading);
  }
  elsif ('play.info.artistDescription' eq $_->{node})
  {
    $reading = encode_utf8(!ref($_->{value}->{c8_array}) ? $_->{value}->{c8_array} : '');

    readingsBulkUpdateIfChanged($hash, 'currentArtistDescription', $reading);
  }
  elsif ('play.info.description' eq $_->{node})
  {
    $reading = encode_utf8(!ref($_->{value}->{c8_array}) ? $_->{value}->{c8_array} : '');

    readingsBulkUpdateIfChanged($hash, 'description', $reading);
  }
  elsif ('play.errorStr' eq $_->{node})
  {
    $reading = encode_utf8(!ref($_->{value}->{c8_array}) ? $_->{value}->{c8_array} : '');

    readingsBulkUpdateIfChanged($hash, 'errorStr', $reading);
  }
}


sub SIRD_SendRequest($$$$$$;$)
{
  my ($hash, $cmd, $request, $value, $keepalive, $callback, $cl) = @_;
  my $name = $hash->{NAME};
  my $ip = InternalVal($name, 'IP', undef);
  my $pin = InternalVal($name, 'PIN', '1234');
  my $sid = '';

  return undef if (IsDisabled($name));

  if (defined($ip))
  {
    if ('GET' eq $cmd)
    {
      $_ = $cmd.'/'.$request.'?pin='.$pin;
    }
    elsif ('GET_MULTIPLE' eq $cmd)
    {
      $_ = $cmd.'?pin='.$pin.'&'.$request;
    }
    elsif ('GET_NOTIFIES' eq $cmd)
    {
      $sid = $hash->{helper}{sid} if (defined($hash->{helper}{sid}));

      $_ = $cmd.'?pin='.$pin.'&sid='.$sid
    }
    elsif ('SET' eq $cmd)
    {
      $_ = $cmd.'/'.$request.'?pin='.$pin.'&value='.$value;
    }
    elsif ('LIST_GET_NEXT' eq $cmd)
    {
      $_ = $cmd.'/'.$request.'?pin='.$pin.'&maxItems='.$value;
    }
    else
    {
      $_ = $cmd.'?pin='.$pin;
    }

    my $param = {
                  url        => 'http://'.$ip.':80/fsapi/'.$_,
                  timeout    => (0 == $keepalive ? 6 : 60),
                  keepalive  => $keepalive,
                  hash       => $hash,
                  cmd        => $cmd,
                  request    => $request,
                  value      => $value,
                  method     => 'GET',
                  callback   => $callback
                };

    if (defined($cl))
    {
      $param->{cl} = $cl;
    }
    else
    {
      $param->{cl} = $hash->{CL};
    }

    HttpUtils_NonblockingGet($param);
  }
}


sub SIRD_ParseNotifies($$$)
{
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my $xml;
  my $notifications = AttrVal($name, 'notifications', 0);

  if ('' ne $err)
  {
    Log3 $name, 5, $name.': Error while requesting '.$param->{url}.' - '.$err;
  }
  elsif ('' ne $data)
  {
    Log3 $name, 5, $name.': URL '.$param->{url}." returned:\n".$data;

    eval {$xml = xmlin($data, keeproot => 0);};

    if (!$@ && ('FS_OK' eq $xml->{status}) && exists($xml->{notify}))
    {
      Log3 $name, 5, $name.': Notifications '.$param->{cmd}.' successful.';

      readingsBeginUpdate($hash);

      foreach (@{forcearray($xml->{notify})})
      {
        if (exists($_->{node}))
        {
          $_->{node} = substr($_->{node}, 10);

          SIRD_SetReadings($hash);
        }
      }

      readingsEndUpdate($hash, 1);
    }
    elsif (!$@ && ('FS_TIMEOUT' eq $xml->{status}))
    {
      # do nothing here
    }
    else
    {
      if ('404 Error' eq $data)
      {
        SIRD_SendRequest($hash, 'CREATE_SESSION', '', 0, 0, \&SIRD_ParseLogin);
        delete($hash->{helper}{notifications});
      }
      else
      {
        Log3 $name, 3, $name.': Notifications '.$param->{cmd}.' failed.';
      }
    }
  }

  HttpUtils_Close($param);

  if ((0 != $notifications) && exists($hash->{helper}{sid}))
  {
    # restart notifications
    SIRD_SendRequest($hash, 'GET_NOTIFIES', '', 0, 1, \&SIRD_ParseNotifies);

    Log3 $name, 5, $name.': Notifications restarted';
  }
}


sub SIRD_ParseMultiple($$$)
{
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my $xml;

  if ('' ne $err)
  {
    Log3 $name, 5, $name.': Error while requesting '.$param->{url}.' - '.$err;
  }
  elsif ('' ne $data)
  {
    Log3 $name, 5, $name.': URL '.$param->{url}." returned:\n".$data;

    eval {$xml = xmlin($data, keeproot => 0);};

    readingsBeginUpdate($hash);

    if (!$@ && exists($xml->{fsapiResponse}))
    {
      Log3 $name, 5, $name.': Multiple '.$param->{cmd}.' successful.';

      foreach (@{forcearray($xml->{fsapiResponse})})
      {
        if (exists($_->{node}) && exists($_->{status}) && exists($_->{value}) && ('FS_OK' eq $_->{status}))
        {
          $_->{node} = substr($_->{node}, 10);

          SIRD_SetReadings($hash);
        }
      }
    }
    else
    {
      SIRD_ClearReadings($hash);
    }

    readingsEndUpdate($hash, 1);
  }
}


sub SIRD_ParseGeneral($$$)
{
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my $xml;

  if ('' ne $err)
  {
    Log3 $name, 5, $name.': Error while requesting '.$param->{url}.' - '.$err;
  }
  elsif ('' ne $data)
  {
    Log3 $name, 5, $name.': URL '.$param->{url}." returned:\n".$data;

    eval {$xml = xmlin($data, keeproot => 0);};

    if (!$@ && ('FS_OK' eq $xml->{status}))
    {
      Log3 $name, 5, $name.': General '.$param->{cmd}.' successful.';

      if ('GET' eq $param->{cmd})
      {
        $xml->{node} = substr($param->{request}, 10);
        $_ = $xml;

        readingsBeginUpdate($hash);
        SIRD_SetReadings($hash);
        readingsEndUpdate($hash, 1);
      }
    }
    elsif ($xml->{status} !~ /FS_NODE/)
    {
      Log3 $name, 5, $name.': General '.$param->{request}.' failed.';
    }
  }
}


sub SIRD_ParseLogin($$$)
{
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my $xml;

  if ('' ne $err)
  {
    Log3 $name, 5, $name.': Error while requesting '.$param->{url}.' - '.$err;
  }
  elsif ('' ne $data)
  {
    Log3 $name, 5, $name.': URL '.$param->{url}." returned:\n".$data;

    eval {$xml = xmlin($data, keeproot => 0);};

    if (!$@ && ('FS_OK' eq $xml->{status}))
    {
      Log3 $name, 5, $name.': Login successful.';

      $hash->{helper}{sid} = $xml->{sessionId};
    }
    else
    {
      Log3 $name, 3, $name.': Login failed.';
    }
  }
}


sub SIRD_ParsePower($$$)
{
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my $xml;

  if ('' ne $err)
  {
    Log3 $name, 5, $name.': Error while requesting '.$param->{url}.' - '.$err;
  }
  elsif ('' ne $data)
  {
    Log3 $name, 5, $name.': URL '.$param->{url}." returned:\n".$data;

    eval {$xml = xmlin($data, keeproot => 0);};

    if (!$@ && ('FS_OK' eq $xml->{status}))
    {
      Log3 $name, 5, $name.': Power '.$param->{cmd}.' successful.';

      if ('GET' eq $param->{cmd})
      {
        readingsSingleUpdate($hash, 'power', (1 == $xml->{value}->{u8} ? 'on' : 'off'), 1);
        readingsSingleUpdate($hash, 'presence', 'present', 1);
      }
      elsif ('SET' eq $param->{cmd})
      {
        readingsSingleUpdate($hash, 'power', (1 == $param->{value} ? 'on' : 'off'), 1);
        readingsSingleUpdate($hash, 'presence', 'present', 1);
      }
    }
    else
    {
      readingsSingleUpdate($hash, 'power', '', 1);
      readingsSingleUpdate($hash, 'presence', 'absent', 1);

      if (1 == AttrVal($name, 'autoLogin', 1))
      {
        SIRD_SendRequest($hash, 'CREATE_SESSION', '', 0, 0, \&SIRD_ParseLogin);
        #SIRD_SendRequest($hash, 'SET', 'netRemote.sys.info.controllerName', 'FHEM', 0, \&SIRD_ParseController);
      }
    }
  }
}


sub SIRD_ParsePlay($$$)
{
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my $xml;

  if ('' ne $err)
  {
    Log3 $name, 5, $name.': Error while requesting '.$param->{url}.' - '.$err;
  }
  elsif ('' ne $data)
  {
    Log3 $name, 5, $name.': URL '.$param->{url}." returned:\n".$data;

    eval {$xml = xmlin($data, keeproot => 0);};

    if (!$@ && ('FS_OK' eq $xml->{status}))
    {
      Log3 $name, 5, $name.': Play '.$param->{cmd}.' successful.';

      if ('GET' eq $param->{cmd})
      {
        my @result = ('idle', 'buffering', 'playing', 'paused', 'rebuffering', 'error', 'stopped');

        readingsSingleUpdate($hash, 'playStatus', ($xml->{value}->{u8} < 7 ? $result[$xml->{value}->{u8}] : 'unknown'), 1);
      }
      elsif ('SET' eq $param->{cmd})
      {
        my @result = ('stopped', 'buffering', 'paused', 'buffering', 'buffering');

        readingsSingleUpdate($hash, 'playStatus', ($param->{value} < 5 ? $result[$param->{value}] : 'error'), 1);
      }
    }
    else
    {
      if ('GET' eq $param->{cmd})
      {
        readingsSingleUpdate($hash, 'playStatus', 'error', 1);
      }
      elsif ('SET' eq $param->{cmd})
      {
        readingsSingleUpdate($hash, 'playStatus', 'not supported', 1);
      }
    }
  }
}


sub SIRD_ParseVolume($$$)
{
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my $xml;

  if ('' ne $err)
  {
    Log3 $name, 5, $name.': Error while requesting '.$param->{url}.' - '.$err;
  }
  elsif ('' ne $data)
  {
    Log3 $name, 5, $name.': URL '.$param->{url}." returned:\n".$data;

    eval {$xml = xmlin($data, keeproot => 0);};

    if (!$@ && ('FS_OK' eq $xml->{status}))
    {
      my $volumeSteps = ReadingsVal($name, '.volumeSteps', 20);

      Log3 $name, 5, $name.': Volume '.$param->{cmd}.' successful.';

      if ('GET' eq $param->{cmd})
      {
        readingsSingleUpdate($hash, 'volume', int($xml->{value}->{u8} * (100 / $volumeSteps)), 1) if (ReadingsVal($name, 'volume', -1) ne int($xml->{value}->{u8} * (100 / $volumeSteps)));
        readingsSingleUpdate($hash, 'volumeStraight', int($xml->{value}->{u8}), 1) if (ReadingsVal($name, 'volumeStraight', -1) ne int($xml->{value}->{u8}));
      }
      elsif ('SET' eq $param->{cmd})
      {
        readingsSingleUpdate($hash, 'volume', int($param->{value} * (100 / $volumeSteps)), 1);
        readingsSingleUpdate($hash, 'volumeStraight', int($param->{value}), 1);
      }
    }
    else
    {
      Log3 $name, 3, $name.': Volume '.$param->{cmd}.' failed.';
    }
  }
}


sub SIRD_ParseMute($$$)
{
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my $xml;

  if ('' ne $err)
  {
    Log3 $name, 5, $name.': Error while requesting '.$param->{url}.' - '.$err;
  }
  elsif ('' ne $data)
  {
    Log3 $name, 5, $name.': URL '.$param->{url}." returned:\n".$data;

    eval {$xml = xmlin($data, keeproot => 0);};

    if (!$@ && ('FS_OK' eq $xml->{status}))
    {
      Log3 $name, 5, $name.': Mute '.$param->{cmd}.' successful.';

      if ('GET' eq $param->{cmd})
      {
        readingsSingleUpdate($hash, 'mute', (1 == $xml->{value}->{u8} ? 'on' : 'off'), 1);
      }
      elsif ('SET' eq $param->{cmd})
      {
        readingsSingleUpdate($hash, 'mute', (1 == $param->{value} ? 'on' : 'off'), 1);
      }
    }
    else
    {
      Log3 $name, 3, $name.': Mute '.$param->{cmd}.' failed.';
    }
  }
}


sub SIRD_ParseShuffle($$$)
{
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my $xml;

  if ('' ne $err)
  {
    Log3 $name, 5, $name.': Error while requesting '.$param->{url}.' - '.$err;
  }
  elsif ('' ne $data)
  {
    Log3 $name, 5, $name.': URL '.$param->{url}." returned:\n".$data;

    eval {$xml = xmlin($data, keeproot => 0);};

    if (!$@ && ('FS_OK' eq $xml->{status}))
    {
      Log3 $name, 5, $name.': Shuffle '.$param->{cmd}.' successful.';

      if ('GET' eq $param->{cmd})
      {
        readingsSingleUpdate($hash, 'shuffle', (1 == $xml->{value}->{u8} ? 'on' : 'off'), 1);
      }
      elsif ('SET' eq $param->{cmd})
      {
        readingsSingleUpdate($hash, 'shuffle', (1 == $param->{value} ? 'on' : 'off'), 1);
      }
    }
    else
    {
      Log3 $name, 3, $name.': Shuffle '.$param->{cmd}.' failed.';
    }
  }
}


sub SIRD_ParseRepeat($$$)
{
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my $xml;

  if ('' ne $err)
  {
    Log3 $name, 5, $name.': Error while requesting '.$param->{url}.' - '.$err;
  }
  elsif ('' ne $data)
  {
    Log3 $name, 5, $name.': URL '.$param->{url}." returned:\n".$data;

    eval {$xml = xmlin($data, keeproot => 0);};

    if (!$@ && ('FS_OK' eq $xml->{status}))
    {
      Log3 $name, 5, $name.': Repeat '.$param->{cmd}.' successful.';

      if ('GET' eq $param->{cmd})
      {
        readingsSingleUpdate($hash, 'repeat', (1 == $xml->{value}->{u8} ? 'on' : 'off'), 1);
      }
      elsif ('SET' eq $param->{cmd})
      {
        readingsSingleUpdate($hash, 'repeat', (1 == $param->{value} ? 'on' : 'off'), 1);
      }
    }
    else
    {
      Log3 $name, 3, $name.': Repeat '.$param->{cmd}.' failed.';
    }
  }
}


sub SIRD_ParseNavState($$$)
{
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my $xml;

  if ('' ne $err)
  {
    Log3 $name, 5, $name.': Error while requesting '.$param->{url}.' - '.$err;
  }
  elsif ('' ne $data)
  {
    Log3 $name, 5, $name.': URL '.$param->{url}." returned:\n".$data;

    eval {$xml = xmlin($data, keeproot => 0);};

    if (!$@ && ('FS_OK' eq $xml->{status}))
    {
      Log3 $name, 5, $name.': NavState '.$param->{cmd}.' successful.';
    }
    else
    {
      Log3 $name, 3, $name.': NavState '.$param->{cmd}.' failed.';
    }
  }
}


sub SIRD_ParseInputs($$$)
{
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my $xml;

  if ('' ne $err)
  {
    Log3 $name, 5, $name.': Error while requesting '.$param->{url}.' - '.$err;
  }
  elsif ('' ne $data)
  {
    Log3 $name, 5, $name.': URL '.$param->{url}." returned:\n".$data;

    eval {$xml = xmlin($data, keeproot => 0);};

    if (!$@ && ('FS_OK' eq $xml->{status}))
    {
      if ('SET' eq $param->{cmd})
      {
        my $inputReading = ReadingsVal($name, '.inputs', '');

        if ($inputReading =~ /$param->{value}:(.*?)(?:,|$)/)
        {
          readingsSingleUpdate($hash, 'input', $1, 1) if ($1 ne ReadingsVal($name, 'input', ''));
        }
      }
      else
      {
        my $inputs = '';

        Log3 $name, 5, $name.': Inputs '.$param->{cmd}.' successful.';

        foreach my $item (@{forcearray($xml->{item})})
        {
          if (exists($item->{key}) && exists($item->{field}) && (scalar(@{forcearray($item->{field})}) >= 1))
          {
            foreach my $field (@{forcearray($item->{field})})
            {
              if (exists($field->{name}) && ('label' eq $field->{name}) && !ref($field->{c8_array}))
              {
                $inputs .= ',' if ('' ne $inputs);
                $inputs .= $item->{key}.':'.lc($field->{c8_array});
              }
            }
          }
        }

        $inputs =~ s/\s//g;

        if ('' ne $inputs)
        {
          readingsSingleUpdate($hash, '.inputs', $inputs, 1);
        }
        else
        {
          Log3 $name, 3, $name.': Something went wrong by parsing the inputs.';
        }
      }
    }
    else
    {
      Log3 $name, 3, $name.': Inputs '.$param->{cmd}.' failed.';
    }
  }
}


sub SIRD_ParsePresets($$$)
{
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my $xml;

  if ('' ne $err)
  {
    Log3 $name, 5, $name.': Error while requesting '.$param->{url}.' - '.$err;
  }
  elsif ('' ne $data)
  {
    Log3 $name, 5, $name.': URL '.$param->{url}." returned:\n".$data;

    eval {$xml = xmlin($data, keeproot => 0);};

    if (!$@ && ('FS_OK' eq $xml->{status}))
    {
      if ('SET' eq $param->{cmd})
      {
        my $input = ReadingsVal($name, 'input', '');
        my $presetReading = ReadingsVal($name, '.'.$input.'presets', '');

        if ($presetReading =~ /$param->{value}:(.*?)(?:,|$)/)
        {
          readingsSingleUpdate($hash, 'preset', $1, 1);
        }

        readingsSingleUpdate($hash, '.lastPreset', $param->{value}, 1);
      }
      else
      {
        my $presets = '';
        my $input = ReadingsVal($name, 'input', '');

        Log3 $name, 5, $name.': Presets '.$param->{cmd}.' successful.';

        foreach my $item (@{forcearray($xml->{item})})
        {
          if (exists($item->{key}) && exists($item->{field}) && (scalar(@{forcearray($item->{field})}) >= 1))
          {
            foreach my $field (@{forcearray($item->{field})})
            {
              if (exists($field->{name}) && ('name' eq $field->{name}) && !ref($field->{c8_array}))
              {
                $_ = $field->{c8_array};
                $_ =~ s/(?:\:|,)//g;

                $presets .= ',' if ('' ne $presets);
                $presets .= $item->{key}.':'.$_;
              }
            }
          }
        }

        $presets =~ s/\s//g;

        readingsSingleUpdate($hash, '.'.$input.'presets', encode_utf8($presets), 1);
        readingsSingleUpdate($hash, '.presets', encode_utf8($presets), 1);
      }
    }
    else
    {
      if ('LIST_GET_NEXT' eq $param->{cmd})
      {
        my $input = ReadingsVal($name, 'input', '');

        readingsSingleUpdate($hash, 'preset', '', 1);
        readingsSingleUpdate($hash, '.'.$input.'presets', '', 1);
      }
    }
  }
}


sub SIRD_ParseNavigation($$$)
{
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my $xml;

  if ('' ne $err)
  {
    Log3 $name, 3, $name.': Error while requesting '.$param->{url}.' - '.$err;
  }
  elsif ('' ne $data)
  {
    Log3 $name, 5, $name.': URL '.$param->{url}." returned:\n".$data;

    eval {$xml = xmlin($data, keeproot => 0);};

    if (!$@ && ('FS_OK' eq $xml->{status}))
    {
      if ('SET' eq $param->{cmd})
      {
        if ('netRemote.nav.action.navigate' eq $param->{request})
        {
          SIRD_StartNavigation($hash, -1, 2, $param->{cl});
        }
      }
      else
      {
        my $nav = '';

        Log3 $name, 5, $name.': Navigation '.$param->{cmd}.' successful.';

        foreach my $item (@{forcearray($xml->{item})})
        {
          if (exists($item->{key}) && exists($item->{field}) && (scalar(@{forcearray($item->{field})}) >= 1))
          {
            my $type = undef;
            my $name = undef;

            foreach my $field (@{forcearray($item->{field})})
            {
              if (exists($field->{name}) && ('name' eq $field->{name}) && !ref($field->{c8_array}))
              {
                $_ = $field->{c8_array};
                $_ =~ s/[^0-9a-zA-Z\.\-\_]+//g;

                $name = $item->{key}.':'.$_;
              }

              if (exists($field->{name}) && ('type' eq $field->{name}))
              {
                $type = $field->{u8};
              }
            }

            if (defined($name) && defined($type))
            {
              $nav .= ',' if ('' ne $nav);
              $nav .= $name.':'.$type;
            }
          }
        }

        $nav =~ s/\s//g;

        if ('' ne $nav)
        {
          if ($nav ne ReadingsVal($name, '.nav', ''))
          {
            readingsSingleUpdate($hash, '.nav', $nav, 1);
          }
        }
        else
        {
          Log3 $name, 3, $name.': Something went wrong by parsing the navigation.';
        }
      }
    }
    else
    {
      if ('LIST_GET_NEXT' eq $param->{cmd})
      {
        readingsSingleUpdate($hash, '.nav', '', 1);
      }
    }
  }
}


sub SIRD_ParseDeviceInfo($$$)
{
  my ($param, $err, $data) = @_;
  my $hash = $param->{hash};
  my $name = $hash->{NAME};
  my $xml;

  if ('' ne $err)
  {
    Log3 $name, 5, $name.': Error while requesting '.$param->{url}.' - '.$err;
  }
  elsif ('' ne $data)
  {
    Log3 $name, 5, $name.': URL '.$param->{url}." returned:\n".$data;

    eval {$xml = xmlin($data, keeproot => 0);};

    if (!$@)
    {
      $hash->{MODEL} = encode_utf8(!ref($xml->{device}->{manufacturer}) && ('' ne $xml->{device}->{manufacturer}) ? $xml->{device}->{manufacturer}.' ' : '').
                       encode_utf8(!ref($xml->{device}->{modelName}) ? $xml->{device}->{modelName} : '');
      $hash->{UDN} = encode_utf8(!ref($xml->{device}->{UDN}) ? $xml->{device}->{UDN} : '');
    }
    else
    {
      Log3 $name, 3, $name.': DeviceInfo failed.';
    }
  }
}


1;

=pod
=begin html

<a name="SIRD"></a>
<h3>SIRD</h3>

<ul>
  <u><b>Module for WLAN Radios with Frontier Silicon Chipset (Lidl (SilverCrest)/Aldi/Medion/Hama and many more...)</b></u>
  <br><br>
  tbd
  <br><br>
  <a name="SIRDinstallation"></a>
  <b>Installation</b>
  <ul><br>
    <code>sudo apt-get install libxml-bare-perl</code><br>
  </ul>
  <br><br>
  <a name="SIRDdefine"></a>
  <b>Define</b>
  <ul><br>
    <code>define &lt;name&gt; SIRD &lt;ip&gt; &lt;pin&gt; &lt;interval&gt;</code>
    <br><br>
    Example:
    <ul><br>
      <code>define MySird SIRD 192.168.1.100 1234 10</code><br>
    </ul>
    <br>
    tbd
  </ul>
  <br><br>
  <a name="SIRDset"></a>
  <b>Set</b>
  <ul>
    <li>login - Connects the radio and creates a new session. Not needed if autoLogin is activated (default).</li>
    <li>stop - stop the playback</li>
    <li>play - start the playback</li>
    <li>pause - pause the playback</li>
    <li>next - switch to next titel/station</li>
    <li>previous - switch to previous titel/station</li>
    <li>input - switch to another input</li>
    <li>&lt;input&gt;preset - switch to another preset</li>
    <li>presetUp - switch to the next preset</li>
    <li>presetDown - switch to the previous preset</li>
    <li>volume - set a new volume 0 - 100</li>
    <li>volumeStraight - set a device specific volume 0 - X</li>
    <li>volumeUp - increase the volume by 1</li>
    <li>volumeDown - decrease the volume by 1</li>
    <li>mute - on/off/toggle</li>
    <li>shuffle - on/off</li>
    <li>repeat - on/off</li>
    <li>statusRequest - update all readings</li>
    <li>speak - text to speech for up to 100 chars</li>
    <br>
  </ul>
  <br><br>
  <a name="SIRDget"></a>
  <b>Get</b>
  <ul>
    <li>inputs - retrieve all inputs from the radio to be used as set command (normally part of the background update process)</li>
    <li>presets - retrieve all presets from the radio to be used as set command (normally part of the background update process)</li>
    <li>ls - list all available navigation items (works for FHEMWEB and Telnet only). To navigate with telnet just run get &lt;device&gt; ls first and afterwards: get &lt;device&gt; ls &lt;index&gt; &lt;type&gt;.</li>
    <br>
  </ul>
  <br><br>
  <a name="SIRDattribute"></a>
  <b>Attributes</b>
  <ul>
    <li><b>disable:</b> disable the module (no update anymore)<br></li>
    <li><b>autoLogin:</b> module tries to automatically login into the radio if needed (default: auto login activated)<br></li>
    <li><b>playCommands:</b> can be used to define the mapping of play commands (default: 0:stop,1:play,2:pause,3:next,4:previous)<br></li>
    <li><b>compatibilityMode:</b> This mode is activated by default and should work for all radios. It is highly recommended to disable the compatibility mode if possible because it needs a lot of ressources.<br></li>
    <li><b>maxNavigationItems:</b> maximum number of navigation items to get by each ls command (default: 100)<br></li>
    <li><b>ttsInput:</b> input for text to speech (default: dmr)<br></li>
    <li><b>ttsLanguage:</b> language setting for text to speech output (default: de)<br></li>
    <li><b>ttsVolume:</b> volume setting for text to speech output (default: 25)<br></li>
    <li><b>ttsWaitTimes:</b> wait times for tts output (default: 0:2:0:2:0:0 = PowerOn:LoadStream:SetVolumeTTS:SetVolumeNormal:SetInput:PowerOff)<br></li>
    <li><b>updateAfterSet:</b> enable or disable the update of all readings after any set command was triggered (default: enabled)<br></li>
    <li><b>notifications:</b> Enable or disable notifications (default: disabled). It may be that you will get some readings faster if this feature is enabled (noticeable for big update cycles only).<br></li>
    <br>
  </ul>
</ul>

=end html
=cut
