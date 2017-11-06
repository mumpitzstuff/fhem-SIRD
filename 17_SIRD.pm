# $Id: 17_SIRD.pm 41052 2017-03-28 16:41:14Z joergbackus $
####################################################################################################
package main;

use strict;
use warnings;
use HttpUtils;
use Encode;
use JSON;
use XML::Simple qw(:strict);
use Time::HiRes qw(gettimeofday sleep);


sub SIRD_Define($$$);
sub SIRD_Undefine($$);
sub SIRD_Set($@);
sub SIRD_Get($@);
sub SIRD_Com ($$$$$);
sub SIRD_space2sub ($);
sub SIRD_Login($);
sub SIRD_Power($$);


sub SIRD_Initialize($)
{
  my ($hash) = @_;
  $hash->{GetFn}    = "SIRD_Get";
  $hash->{SetFn}    = "SIRD_Set";
  $hash->{DefFn}    = "SIRD_Define";
  $hash->{AttrList} = "volumeStep ".
                      "navListItems ".
                      "presetListRequestMode ".
                      $readingFnAttributes;

  Log 2, "SIRD Init module";
}


    
sub SIRD_Define($$$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  return "wrong syntax: define <name> SIRD IP Password TYP [interval]" if (scalar(@a) < 4);

  $hash->{IP} = $a[2];

  if ((scalar(@a) == 6) || (scalar(@a) == 5))
  {
    $hash->{PASSWORD} = $a[3];
  }
  else
  {
    $hash->{PASSWORD} = "";
  }

  $hash->{Model} = $a[4];
  
  my $result = SIRD_Login($hash);
  if (defined($result))
  {
    $hash->{STATE} = "initialized";
  }
  
  if (defined($a[5]) && ($a[5] > 10))
  {
    $hash->{INTERVAL} = $a[5];
  }
  else
  {
    $hash->{INTERVAL} = 30;
  }

  InternalTimer(gettimeofday() + int(rand(30)), 'SIRD_StartStatus', $hash, 0);
  return undef;
}


sub SIRD_Undefine($$)
{
  my ($hash, $name) = @_;

  RemoveInternalTimer($hash);
  BlockingKill($hash->{helper}{RUNNING_PID}) if (defined($hash->{helper}{RUNNING_PID}));
  return undef;
}


    
sub SIRD_Set($@)
{
  my ($hash, @a) = @_;
  my $namex = $hash->{NAME};
  my $preset  = "";
  my $presetList1  = "";
  my $presetList2  = "";
  my $presetListC  = '0';
  my $navList = "<<BACK<<";
  my $incer   = 0;
  my $input1 = "nix";
  my $listMethode = "new";

  #if (defined($hash->{helper}->{presetAll})) 
  #{
  #  $preset = $hash->{helper}->{presetAll};
  #  $preset = encode_utf8($preset);
  #}

  #if (defined($hash->{helper}->{preset1_5}) && 
  #    defined($hash->{READINGS}{"power"}) &&
  #    ($hash->{READINGS}{"presetList_1-5"}{VAL} ne $hash->{helper}->{preset1_5}) &&
  #    ($hash->{READINGS}{"power"}{VAL} eq "on")) 
  #{
  #  readingsSingleUpdate($hash, "presetList_1-5", $hash->{helper}->{preset1_5}, 1);
  #}
  
  #if (defined($hash->{helper}->{preset6_0}) &&
  #    defined($hash->{READINGS}{"power"}) &&
  #    ($hash->{READINGS}{"presetList_6-0"}{VAL} ne $hash->{helper}->{preset6_0}) && 
  #    ($hash->{READINGS}{"power"}{VAL} eq "on")) 
  #{
  #  readingsSingleUpdate($hash, "presetList_6-0", $hash->{helper}->{preset6_0}, 1);
  #}

  if (defined($hash->{helper}->{navList}) && 
      ref($hash->{helper}->{navList}->{item}) eq "ARRAY")
  {
    if (ref($hash->{helper}->{navList}->{'item'}) eq "ARRAY")
    {
      $incer = 0;
      for my $item (@{ $hash->{helper}->{navList}->{'item'}})
      {
        if (exists($item->{'field'}[0]->{c8_array}) && 
            ref($item->{'field'}[0]->{c8_array}) ne "HASH")
        {
          @{$item->{'field'}}[0]->{c8_array} = SIRD_xml2txt(SIRD_space2sub(@{$item->{'field'}}[0]->{c8_array}));

          if ($navList ne "")
          {
            $navList .= ',';
          }
          $incer = $incer + 1;
          $navList .= @{$item->{'field'}}[0]->{c8_array};
        }
      }
      $navList .= ",>>FORWARD>>";
      $navList = encode_utf8($navList);
      $hash->{helper}->{navList}->{keyErster} = $hash->{helper}->{navList}->{item}[0]->{key};
      $hash->{helper}->{navList}->{keyLetzter} = $hash->{helper}->{navList}->{item}[int($incer - 1)]->{key};
    }
  }

  return "no set value specified" if (scalar(@a) < 2);
  
  if ($hash->{Model} eq "SIRD-AUTOMATIC") 
  {
    if (defined($hash->{helper}->{inputAll})) 
    {
      $input1 = $hash->{helper}->{inputAll};
    }
    else 
    {
      $input1 = "InternetRadio";
    }
    
    my $navList1 = $navList;
    my $navList2 = $navList;
    return "Unknown argument $a[1], choose one of on:noArg off:noArg play:noArg pause:noArg stop:noArg channelUp:noArg channelDown:noArg ". 
           "volumeStraight:slider,0,1,20 volume:slider,0,1,100 volumeUp volumeDown mute:on,off,toggle shuffle:on,off repeat:on,off input:$input1 ". 
           "statusRequest:noArg remoteState:on,off clearreadings:noArg ". 
           "navListRequest navActionSelItem navActionNavi navCapsRequest searchTerm navList:". 
           $navList." ". 
           "presetListRequest:noArg preset:".
           $preset if ($a[1] eq "?");
  }

  if ($hash->{Model} eq "sird")
  {
    return "Unknown argument $a[1], choose one of on:noArg off:noArg play:noArg pause:noArg stop:noArg channelUp:noArg channelDown:noArg ". 
           "volumeStraight:slider,0,1,20 volume:slider,0,1,100 volumeUp volumeDown mute:on,off,toggle shuffle:on,off repeat:on,off input:InternetRadio ". 
           "statusRequest:noArg remoteState:on,off clearreadings:noArg ". 
           "navListRequest navActionSelItem navActionNavi navCapsRequest searchTerm navList:". 
           $navList." ". 
           "presetListRequest:noArg preset:". 
           $preset if ($a[1] eq "?");
  }

  if ($hash->{Model} eq "sird14" || $hash->{Model} eq "sird14a2" || $hash->{Model} eq "sird14b1")
  {
    my $input1 = "InternetRadio,MediaPlayer,DAB-Radio,FM-Radio,AUX";
    return "Unknown argument $a[1], choose one of on:noArg off:noArg play:noArg pause:noArg stop:noArg channelUp:noArg channelDown:noArg ". 
           "volumeStraight:slider,0,1,20 volume:slider,0,5,100 volumeUp volumeDown mute:on,off,toggle shuffle:on,off repeat:on,off input:$input1 ". 
           "statusRequest:noArg remoteState:on,off clearreadings:noArg ". 
           "navListRequest navActionSelItem navActionNavi navCapsRequest searchTerm navList:". 
           $navList." ". 
           "presetListRequest:noArg preset:". 
           $preset if ($a[1] eq "?");
  }

  if ($hash->{Model} eq "sird14c2")
  {
    my $input1 = "InternetRadio,Tidal,Deezer,Qobuz,Spotify,MediaPlayer,DAB-Radio,FM-Radio,AUX";
    return "Unknown argument $a[1], choose one of on:noArg off:noArg play:noArg pause:noArg stop:noArg channelUp:noArg channelDown:noArg ". 
           "volumeStraight:slider,0,5,20 volume:slider,0,1,100 volumeUp volumeDown mute:on,off,toggle shuffle:on,off repeat:on,off input:$input1 ". 
           "statusRequest:noArg remoteState:on,off clearreadings:noArg ". 
           "navListRequest navActionSelItem navActionNavi navCapsRequest searchTerm navList:". 
           $navList." ". 
           "presetListRequest:noArg preset:". 
           $preset if ($a[1] eq "?");
  }

  if ($hash->{Model} eq "IR110")
  {
    return "Unknown argument $a[1], choose one of on:noArg off:noArg play:noArg pause:noArg stop:noArg channelUp:noArg channelDown:noArg ". 
           "volume:slider,0,1,100 volumeStraight:slider,0,1,20 volumeUp volumeDown mute:on,off,toggle shuffle:on,off repeat:on,off input:InternetRadio,Spotify,MediaPlayer,DAB-Radio,FM-Radio,AUX ". 
           "statusRequest:noArg remoteState:on,off clearreadings:noArg ". 
           "navListRequest navActionSelItem navActionNavi navCapsRequest searchTerm navList:". 
           $navList." ". 
           "presetListRequest:noArg preset:". 
           $preset if ($a[1] eq "?");
  }

  if ($hash->{Model} eq "MD87238")
  {
    return "Unknown argument $a[1], choose one of on:noArg off:noArg play:noArg pause:noArg stop:noArg channelUp:noArg channelDown:noArg ". 
           "volume:slider,0,1,100 volumeStraight:slider,0,1,20 volumeUp volumeDown mute:on,off,toggle shuffle:on,off repeat:on,off input:InternetRadio,MediaPlayer,FM-Radio,AUX ". 
           "statusRequest:noArg remoteState:on,off clearreadings:noArg ". 
           "navListRequest navActionSelItem navActionNavi navCapsRequest searchTerm navList:". 
           $navList." ". 
           "presetListRequest:noArg preset:". 
           $preset if ($a[1] eq "?");
  }

  if ($hash->{Model} eq "MD87385")
  {
    return "Unknown argument $a[1], choose one of on:noArg off:noArg play:noArg pause:noArg stop:noArg channelUp:noArg channelDown:noArg ". 
           "volume:slider,0,1,100 volumeStraight:slider,0,1,20 volumeUp volumeDown mute:on,off,toggle shuffle:on,off repeat:on,off input:InternetRadio,MediaPlayer,DAB-Radio,FM-Radio,AUX ". 
           "statusRequest:noArg remoteState:on,off clearreadings:noArg ". 
           "navListRequest navActionSelItem navActionNavi navCapsRequest searchTerm navList:". 
           $navList." ". 
           "presetListRequest:noArg preset:". 
           $preset if ($a[1] eq "?");
  }

  if ($hash->{Model} eq "TechniSatDR580")
  {
    return "Unknown argument $a[1], choose one of on:noArg off:noArg play:noArg pause:noArg stop:noArg channelUp:noArg channelDown:noArg ". 
           "volume:slider,0,1,100 volumeStraight:slider,0,1,20 volumeUp volumeDown mute:on,off,toggle shuffle:on,off repeat:on,off input:InternetRadio,Spotify,MediaPlayer,DAB-Radio,FM-Radio,AUX,CD,Bluetooth ". 
           "statusRequest:noArg remoteState:on,off clearreadings:noArg ". 
           "navListRequest navActionSelItem navActionNavi navCapsRequest searchTerm navList:". 
           $navList." ". 
           "presetListRequest:noArg preset:". 
           $preset if ($a[1] eq "?");
  }

  my $name       = shift @a;
  my $setcommand = shift @a;
  my $params     = join( ' ', @a );
  my $helper     = '0';
  my $helper1    = 0;

  Log 5, "SIRD set $name $setcommand $params";
  
  $helper = SIRD_Power($name, -1);
  readingsSingleUpdate($hash, 'power', defined($helper) ? $helper : ' ', 1);
  readingsSingleUpdate($hash, 'presence', (defined($helper) && $helper ne 'absent') ? 'present' : 'absent', 1);

  if (!defined($helper) || !defined( $hash->{SESSIONID}))
  {
    SIRD_Login($name);
  }

  if ($setcommand eq "on")
  {
    $_ = SIRD_Power($name, "on");
    readingsSingleUpdate($hash, 'power', defined($_) ? $_ : ' ', 1);
    readingsSingleUpdate($hash, 'presence', (defined($_) && $_ ne 'absent') ? 'present' : 'absent', 1);
  }
  elsif ($setcommand eq "off")
  {
    $_ = SIRD_Power($name, "off");
    readingsSingleUpdate($hash, 'power', defined($_) ? $_ : ' ', 1);
    readingsSingleUpdate($hash, 'presence', (defined($_) && $_ ne 'absent') ? 'present' : 'absent', 1);
  }
  elsif ($setcommand eq "input")
  {
    my $helper;
    my $helper2;
    
    if ( defined( $hash->{helper}->{inputAll} )) {
      if ( $hash->{helper}->{inputAll} ne "0" ) {
        my $idxInput = '0';
        my @valIn = split(',', $hash->{helper}->{inputAll});
          foreach my $valIn1 (@valIn) {
          if ($params eq $valIn1) {
            $helper = $idxInput;
            $helper2 = $valIn1;
          }
          $idxInput++;
        }
        $idxInput = '0';
      }
    }
    
    @_ = SIRD_Input($name, $helper);
    if (scalar(@_) == 5)
    {
      $hash->{helper}->{input1} = $_[0] if (defined($_[0]));
      $hash->{helper}->{input2} = $_[1] if (defined($_[1]));
      $hash->{helper}->{inputRead} = $_[2] if (defined($_[2]));
      $hash->{helper}->{inputAll} = $_[3] if (defined($_[3]));
      readingsSingleUpdate($hash, 'input', defined($_[4]) ? $_[4] : '0', 1);
      readingsSingleUpdate($hash, 'inputSelectable', defined($_[2]) ? $_[2] : '0', 1);
    }
  }
  elsif ($setcommand eq "volume")
  {
    my $helper = int($params / 5);
    $_ = SIRD_Volume($name, $helper);
    readingsSingleUpdate($hash, 'volumeStraight', defined($_) ? $_ : ' ', 1);
    readingsSingleUpdate($hash, 'volume', defined($_) ? $_ * 5 : ' ', 1);
  }
  elsif ($setcommand eq "volumeStraight")
  {
    my $helper = int($params);
    $_ = SIRD_Volume($name, $helper);
    readingsSingleUpdate($hash, 'volumeStraight', defined($_) ? $_ : ' ', 1);
    readingsSingleUpdate($hash, 'volume', defined($_) ? $_ * 5 : ' ', 1);
  }
  elsif ($setcommand eq "volumeUp")
  {
    my $helper = $hash->{READINGS}{volumeStraight}{VAL};
    if (int($helper) < 20)
    {
      if ($params eq '')
      {
        if ($attr{$name}{"volumeStep"} == '0')
        {
          $helper = $helper + 1;
        }
        else
        {
          $helper = $helper + $attr{$name}{"volumeStep"};
        }
      }
      else
      {
        $helper = $helper + int($params);
      }
      if (int($helper) > 20)
      {
        $helper = 20;
      }
      elsif (int($helper) < 0)
      {
        $helper = 0;
      }
      $_ = SIRD_Volume($name, $helper);
      readingsSingleUpdate($hash, 'volumeStraight', defined($_) ? $_ : ' ', 1);
      readingsSingleUpdate($hash, 'volume', defined($_) ? $_ * 5 : ' ', 1);
    }
  }
  elsif ($setcommand eq "volumeDown")
  {
    my $helper = $hash->{READINGS}{volumeStraight}{VAL};
    if (int($helper) > 0)
    {
      if ($params eq '')
      {
        if ($attr{$name}{"volumeStep"} == '0')
        {
          $helper = $helper - 1;
        }
        else
        {
          $helper = $helper - $attr{$name}{"volumeStep"};
        }
      }
      else
      {
        $helper = $helper - int($params);
      }
      if (int($helper) > 20)
      {
        $helper = 20;
      }
      elsif (int($helper) < 0)
      {
        $helper = 0;
      }
      $_ = SIRD_Volume($name, $helper);
      readingsSingleUpdate($hash, 'volumeStraight', defined($_) ? $_ : ' ', 1);
      readingsSingleUpdate($hash, 'volume', defined($_) ? $_ * 5 : ' ', 1);
    }
  }
  elsif ($setcommand eq "mute")
  {
    if ($params eq "on" || $params eq "off")
    {
      $_ = SIRD_Mute($name, $params);
      readingsSingleUpdate($hash, 'mute', defined($_) ? $_ : ' ', 1);
    }
    elsif ($params eq "toggle")
    {
      if (ReadingsVal($name, "mute", "0") eq "on")
      {
        $helper = "off";
      }
      elsif (ReadingsVal($name, "mute", "0") eq "off")
      {
        $helper = "on";
      }
      $_ = SIRD_Mute($name, $helper);
      readingsSingleUpdate($hash, 'mute', defined($_) ? $_ : ' ', 1);
    }
    else
    {
      Log 1, "SIRD Command Mute wrong Parameter: ".$params;
      return 0;
    }
  }
  elsif ($setcommand eq "stop")
  {
    SIRD_PlayMode($name, "stop");
  }
  elsif ($setcommand eq "play")
  {
    SIRD_PlayMode($name, "play");
  }
  elsif ($setcommand eq "pause")
  {
    SIRD_PlayMode($name, "pause");
  }
  elsif ($setcommand eq "channelUp")
  {
    SIRD_PlayMode($name, "next");
  }
  elsif ($setcommand eq "channelDown")
  {
    SIRD_PlayMode($name, "previous");
  }
  elsif ($setcommand eq "statusRequest")
  {
    SIRD_StartStatus($hash);
  }
  elsif ($setcommand eq "shuffle")
  {
    $_ = SIRD_Shuffle($name, $params);
    readingsSingleUpdate($hash, 'shuffle', defined($_) ? $_ : ' ', 1);
  }
  elsif ($setcommand eq "repeat")
  {
    $_ = SIRD_Repeat($name, $params);
    readingsSingleUpdate($hash, 'repeat', defined($_) ? $_ : ' ', 1);
  }
  elsif ($setcommand eq "navActionSelItem")
  {
    eval {SIRD_Com($name, "netRemote.nav.action.selectItem", 2, $params, 0);};

    if ($@)
    {
      Log 1, "SIRD navActionSelItem error: $@";
      return 0;
    }
  }
  elsif ($setcommand eq "navActionNavi")
  {
    eval {SIRD_Com($name, "netRemote.nav.action.navigate", 2, $params, 0);};

    if ($@)
    {
      Log 1, "SIRD navActionNavi error: $@";
      return 0;
    }
  }
  elsif ($setcommand eq "remoteState")
  {
    $_ = SIRD_RemoteState($name, $params);
    readingsSingleUpdate($hash, 'remoteState', defined($_) ? $_ : ' ', 1);
  }
  elsif ($setcommand eq "searchTerm")
  {
    $_ = SIRD_SearchTerm($name, $params);
    readingsSingleUpdate($hash, 'searchTerm', defined($_) ? $_ : ' ', 1);
  }
  elsif ($setcommand eq "friendlyNameRequest")
  {
    $_ = SIRD_FriendlyName($name, -1);
    readingsSingleUpdate($hash, 'friendlyName', defined($_) ? $_ : ' ', 1);
  }
  elsif ($setcommand eq "versionRequest")
  {
    $_ = SIRD_Version($name, -1);
    readingsSingleUpdate($hash, 'version', defined($_) ? $_ : ' ', 1);
  }
  elsif ($setcommand eq "infoTextRequest")
  {
    $_ = SIRD_InfoText($name, -1);
    readingsSingleUpdate($hash, 'infoText', defined($_) ? $_ : ' ', 1);
  }
  elsif ($setcommand eq "infoNameRequest")
  {
    $_ = SIRD_InfoName($name, -1);
    readingsSingleUpdate($hash, 'currentTitle', defined($_) ? $_ : ' ', 1);
  }
  elsif ($setcommand eq "frequencyRequest")
  {
    $_ = SIRD_Frequency($name, -1);
    readingsSingleUpdate($hash, 'frequency', defined($_) ? $_ : ' ', 1);
  }
  elsif ($setcommand eq "signalStrengthRequest")
  {
    $_ = SIRD_SignalStrength($name, -1);
    readingsSingleUpdate($hash, 'signalStrength', defined($_) ? $_ : ' ', 1);
  }
  elsif ($setcommand eq "navCapsRequest")
  {
    $_ = SIRD_NavCaps($name, -1);
    readingsSingleUpdate($hash, 'navCaps', defined($_) ? $_ : ' ', 1);
  }
  elsif ($setcommand eq "navListRequest")
  {
    $helper = '20';
    $params = '0';

    if (int($attr{$name}{"navListItems"}) != '0' || $attr{$name}{"navListItems"} ne '')
    {
      $helper = $attr{$name}{"navListItems"};
    }

    $hash->{helper}->{navList} = SIRD_NavList($name, int($params), int($params) + int($helper));
  }
  elsif ($setcommand eq "navList")
  {
    if ($params eq "<<BACK<<")
    {
      if (int($hash->{helper}->{navList}->{keyErster}) <= 0)
      {
        eval 
        {
          SIRD_Com($name, "netRemote.nav.action.navigate", 2, "-1", 0);
          $_ = SIRD_NavNumItems($name, -1);
          readingsSingleUpdate($hash, 'navNumItems', defined($_) ? $_ : ' ', 1);
        };
        sleep 2;
        $hash->{helper}->{navList} = SIRD_NavList($name, -1, int($helper));
      }
      else
      {
        $_ = SIRD_NavNumItems($name, -1);
        readingsSingleUpdate($hash, 'navNumItems', defined($_) ? $_ : ' ', 1);
        $helper = 20;
        if (int($attr{$name}{"navListItems"}) != 0 || $attr{$name}{"navListItems"} ne "")
        {
          $helper = $attr{$name}{"navListItems"};
        }
        
        $helper1 = int($hash->{helper}->{navList}->{keyErster}) - $helper;
        if ($helper1 < -1)
        {
          $helper1 = -1;
        }
        sleep 2;
        $hash->{helper}->{navList} = SIRD_NavList($name, int($helper1), int($helper1) + int($helper));
        
        if ($@)
        {
          Log 1, "SIRD NavList back error: $@";
          return 0;
        }
      }
    }
    elsif ($params eq ">>FORWARD>>")
    {
      if (int($hash->{helper}->{navList}->{keyLetzter}) < int($hash->{READINGS}{navNumItems}{VAL}))
      {
        $helper = 20;
        if (int( $attr{$name}{"navListItems"}) != 0)
        {
          $helper = int($attr{$name}{"navListItems"});
        }
        $helper1 = int($hash->{helper}->{navList}->{keyLetzter});
        if ($helper1 < -1)
        {
          $helper1 = -1;
        }
        sleep 2;
        $hash->{helper}->{navList} = SIRD_NavList($name, int($helper1), int($helper1) + int($helper));
        
        if ($@)
        {
          Log 1, "SIRD NavList forward error: $@";
          return 0;
        }
      }
    }
    else
    {
      if (defined($hash->{helper}->{navList}) && ref($hash->{helper}->{navList}->{item}) eq "ARRAY")
      {
        if (ref($hash->{helper}->{navList}->{item}) eq "ARRAY")
        {
          for my $item (@{$hash->{helper}->{navList}->{'item'}})
          {
            if (exists($item->{'field'}[0]->{c8_array}) && ref($item->{'field'}[0]->{c8_array}) ne "HASH")
            {
              if (@{$item->{'field'}}[0]->{c8_array} eq $params)
              {
                if (@{$item->{'field'}}[1]->{u8} == 1)
                {
                  eval {SIRD_Com( $name, "netRemote.nav.action.selectItem", 2, int( $item->{'key'} ), 0);};

                  if ($@)
                  {
                    Log 1, "SIRD navList SelItem error: $@";
                    return 0;
                  }
                }
                else
                {
                  eval {SIRD_Com( $name, "netRemote.nav.action.navigate", 2, int( $item->{'key'} ), 0);};

                  if ($@)
                  {
                    Log 1, "SIRD navList Navigate error: $@";
                    return 0;
                  }
                }

              }
            }
          }
        }
      }
      
      $helper = 20;
      if (int( $attr{$name}{"navListItems"}) != 0 || $attr{$name}{"navListItems"} ne "")
      {
        $helper = $attr{$name}{"navListItems"};
      }
      sleep 2;
      $hash->{helper}->{navList} = SIRD_NavList($name, -1, int($helper));
      $_ = SIRD_NavNumItems($name, -1);
      readingsSingleUpdate($hash, 'navNumItems', defined($_) ? $_ : ' ', 1);
    }
  }
  elsif ($setcommand eq "dABScanRequest")
  {
    $_ = SIRD_DABScan($name, -1);
    readingsSingleUpdate($hash, 'dABScan', defined($_) ? $_ : ' ', 1);
  }
  elsif ($setcommand eq "clearreadings")
  {
    delete $hash->{READINGS};
  }
  elsif ($setcommand eq "presetListRequest")
  {
    @_ = SIRD_PresetList($name, -1);
    if (scalar(@_) == 4)
    {
      $hash->{helper}->{preset} = $_[0] if (defined($_[0]));
      $hash->{helper}->{presetAll} = $_[1] if (defined($_[1]));
      $hash->{helper}->{preset1_5} = $_[2] if (defined($_[2]));
      $hash->{helper}->{preset6_0} = $_[3] if (defined($_[3]));
    }
  }
  elsif ($setcommand eq "preset" && $listMethode eq "old")
  {
    if (defined($hash->{helper}->{preset}) && ref($hash->{helper}->{preset}->{item}) eq "ARRAY")
    {
      if (ref($hash->{helper}->{preset}->{'item'}) eq "ARRAY")
      {
        for my $item (@{$hash->{helper}->{preset}->{'item'}})
        {
          if (exists($item->{'field'}->{c8_array}) && ref($item->{'field'}->{c8_array}) ne "HASH")
          {
            if ($item->{'field'}->{c8_array} eq $params)
            {
              eval {SIRD_Com( $name, "netRemote.nav.action.selectPreset", 2, int( $item->{'key'} ), 0);};
              
              if ($@)
              {
                Log 1, "SIRD preset error: $@";
                return 0;
              }
            }
          }
        }
      }
    }
  }
  elsif ($setcommand eq "preset" && $listMethode eq "new")
  {
    if (defined($hash->{helper}->{preset}) && ref($hash->{helper}->{preset}->{item}) eq "ARRAY")
    {
      if (ref($hash->{helper}->{preset}->{'item'}) eq "ARRAY")
      {
        for my $item (@{$hash->{helper}->{preset}->{'item'}})
        {
          if (exists($item->{'field'}->{c8_array}) && ref($item->{'field'}->{c8_array}) ne "HASH")
          {
            my $item2 = $item->{'field'}->{c8_array};
            $item2 = SIRD_space2sub($item2);

            if ($item2 eq $params)
            {
              eval {SIRD_Com( $name, "netRemote.nav.action.selectPreset", 2, int( $item->{'key'} ), 0);};
              
              if ($@)
              {
                Log 1, "SIRD preset error: $@";
                return 0;
              }
            }
          }
        }
      }
    }
  }
  else
  {
    return "unknown argument $setcommand, choose one of on off play pause stop channelUp channelDown ". 
           "volume volumeStraight volumeUp VolumeDown mute shuffle repeat input ". 
           "statusRequest RemoteState clearreadings friendlyNameRequest versionRequest infoTextRequest infoNameRequest ". 
           "frequencyRequest signalStrengthRequest navListRequest navActionSelItem navActionNavi dABScanRequest";
  }

  $hash->{CHANGED}[0] = $setcommand;
  $hash->{READINGS}{lastcommand}{TIME} = TimeNow();
  $hash->{READINGS}{lastcommand}{VAL} = $setcommand." ".$params;

  if ($setcommand ne "statusRequest")
  {
    SIRD_StartStatus($hash);
  }
  
  return undef;
}



sub SIRD_Get($@)
{
  my ($hash, @a) = @_;
  my $what;
  
  return "argument is missing" if (scalar(@a) != 2);

  $what = $a[1];

  if ($what =~ /^(lastcommand|power|presence|volume|volumeStraight|mute|repeat|shuffle|input|currentArtist|currentAlbum|currentTitle|playStatus|state)$/)
  {
    if (defined($hash->{READINGS}{$what}))
    {
      return $hash->{READINGS}{$what}{VAL};
    }
    else
    {
      if ($what eq "state")
      {
        if ($hash->{READINGS}{"presence"}{VAL} ne "absent")
        {
          return $hash->{READINGS}{"power"}{VAL};
        }
        else
        {
          return $hash->{READINGS}{"presence"}{VAL};
        }
      }
      else
      {
        return "reading not found: $what";
      }
    }
  }

  return "Unknown argument $what, choose one of lastcommand:noArg power:noArg presence:noArg volume:noArg volumeStraight:noArg mute:noArg repeat:noArg shuffle:noArg ".
         "input:noArg currentArtist:noArg currentAlbum:noArg currentTitle:noArg playStatus:noArg state:noArg ".(exists($hash->{READINGS}{output}) ? " output:noArg" : "");
}


sub SIRD_Com($$$$$)
{
  my ($name, $Command, $mode, $value, $value1) = @_;
  my $response = "";
  my $url;
  my $ip = InternalVal($name, 'IP', '0');
  my $password = InternalVal($name, 'PASSWORD', '1234');
  my $sessionId = InternalVal($name, 'SESSIONID', '0');
  
  for (my $i = 0; $i < 3; $i++)
  {
    if (0 == $mode)    #nonspecific
    {
      $url = "http://".$ip.":80/fsapi/".$Command;
      $response = GetFileFromURL($url, 10, "", 1, 5);
    }
    elsif (1 == $mode)    # GET     #/fsapi/GET/netRemote.sys.mode?pin=1337&sid=300029608
    {
      $url = "http://".$ip.":80/fsapi/GET/".$Command."?pin=".$password."&sid=".$sessionId;
      $response = GetFileFromURL($url, 2, "", 1, 5);
    }
    elsif (2 == $mode)    # SET
    {
      $url = "http://".$ip.":80/fsapi/SET/".$Command."?pin=".$password."&sid=".$sessionId."&value=".$value;
      $response = GetFileFromURL($url, 2, "", 1, 5);
    }
    elsif (3 == $mode)    # GETLIST
    {
      $url = "http://".$ip.":80/fsapi/LIST_GET_NEXT/".$Command."/".$value."?pin=".$password."&sid=".$sessionId."&maxItems=".$value1;
      $response = GetFileFromURL($url, 2, "", 1, 5);
    }
    elsif (4 == $mode)    # LIST_GET_NEXT VALID MODES  #/fsapi/LIST_GET_NEXT/netRemote.sys.caps.validModes/-1?pin=1337&sid=300029608&maxItems=100
    {
      $url = "http://".$ip.":80/fsapi/LIST_GET_NEXT/".$Command."?pin=".$password."&sid=".$sessionId."&maxItems=".$value1;
      $response = GetFileFromURL($url, 2, "", 1, 5);
    }
    
    if ($response && ($response =~ /fsapiResponse/))
    {
      Log3 $name, 5, "SIRD (com: ".$Command."): ".$response;
      
      return $response;
    }
    else
    {
      Log3 $name, 5, "SIRD (com error: ".$Command.")";
    }
  }
  
  return undef;
}


sub SIRD_StartStatus($)
{
  my ($hash) = @_;

  if (!(exists($hash->{helper}{RUNNING_PID}))) 
  {
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday() + $hash->{INTERVAL}, "SIRD_StartStatus", $hash, 0);
    
    my $sessionId = defined($hash->{SESSIONID}) ? $hash->{SESSIONID} : '';
    
    $hash->{helper}{RUNNING_PID} = BlockingCall('SIRD_DoStatus', $hash->{NAME}.'|'.$sessionId, 'SIRD_EndStatus', 300, 'SIRD_AbortStatus', $hash) if (defined($hash->{IP}) && defined($hash->{INTERVAL}));
  } 
  else 
  {
    Log3 $hash->{NAME}, 3, $hash->{NAME}.' blocking call already running';
    
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday() + $hash->{INTERVAL}, "SIRD_StartStatus", $hash, 0);
  }
}


sub SIRD_DoStatus(@)
{
  my ($string) = @_;
  my ($name, $sessionId) = split("\\|", $string);
  my %status = ();
    
  $_ = SIRD_Power($name, -1);
  $status{'power'} = $_ if (defined($_));
  Log3 $name, 5, $name.' power: '.$_ if (defined($_));

  if ($_ eq 'absent' || $sessionId eq '')
  {
    $_ = SIRD_Login($name);
    $status{'sessionId'} = $_ if (defined($_));
    Log3 $name, 5, $name.' sessionId: '.$_ if (defined($_));
    
    sleep(2);
    
    $_ = SIRD_Power($name, -1);
    $status{'power'} = $_ if (defined($_));
    Log3 $name, 5, $name.' power: '.$_ if (defined($_));
  }

  if ($_ eq "on")
  {
    my $remoteState;
    
    $_ = SIRD_FriendlyName($name, -1);
    $status{'friendlyName'} = $_ if (defined($_));
    Log3 $name, 5, $name.' friendlyName: '.$_ if (defined($_));
    
    $_ = SIRD_Version($name, -1);
    $status{'version'} = $_ if (defined($_));
    Log3 $name, 5, $name.' version: '.$_ if (defined($_));
    
    $_ = SIRD_ID($name, -1);
    $status{'id'} = $_ if (defined($_));
    Log3 $name, 5, $name.' id: '.$_ if (defined($_));
    
    $_ = SIRD_Volume($name, -1);
    $status{'volume'} = $_ if (defined($_));
    Log3 $name, 5, $name.' volume: '.$_ if (defined($_));
    
    $_ = SIRD_Mute($name, -1);
    $status{'mute'} = $_ if (defined($_));
    Log3 $name, 5, $name.' mute: '.$_ if (defined($_));
    
    @_ = SIRD_Input($name, -1);
    if (scalar(@_) == 5)
    {
      $status{'input0'} = $_[0] if (defined($_[0]));
      $status{'input1'} = $_[1] if (defined($_[1]));
      $status{'input2'} = $_[2] if (defined($_[2]));
      $status{'input3'} = $_[3] if (defined($_[3]));
      $status{'input4'} = $_[4] if (defined($_[4]));
    }
    
    $_ = SIRD_InfoName($name, -1);
    $status{'infoName'} = $_ if (defined($_));
    Log3 $name, 5, $name.' infoName: '.$_ if (defined($_));
    
    $_ = SIRD_InfoText($name, -1);
    $status{'infoText'} = $_ if (defined($_));
    Log3 $name, 5, $name.' infoText: '.$_ if (defined($_));
    
    $remoteState = SIRD_RemoteState($name, -1);
    $status{'remoteState'} = $remoteState if (defined($remoteState));
    Log3 $name, 5, $name.' remoteState: '.$remoteState if (defined($remoteState));
    
    $_ = SIRD_PlayMode($name, -1);
    $status{'playMode'} = $_ if (defined($_));
    Log3 $name, 5, $name.' playMode: '.$_ if (defined($_));
    
    $_ = SIRD_Shuffle($name, -1);
    $status{'shuffle'} = $_ if (defined($_));
    Log3 $name, 5, $name.' shuffle: '.$_ if (defined($_));
    
    $_ = SIRD_Repeat($name, -1);
    $status{'repeat'} = $_ if (defined($_));
    Log3 $name, 5, $name.' repeat: '.$_ if (defined($_));
    
    $_ = SIRD_InfoAlbum($name, -1);
    $status{'infoAlbum'} = $_ if (defined($_));
    Log3 $name, 5, $name.' infoAlbum: '.$_ if (defined($_));
    
    $_ = SIRD_InfoArtist($name, -1);
    $status{'infoArtist'} = $_ if (defined($_));
    Log3 $name, 5, $name.' infoArtist: '.$_ if (defined($_));
    
    $_ = SIRD_PlayRate($name, -1);
    $status{'playRate'} = $_ if (defined($_));
    Log3 $name, 5, $name.' playRate: '.$_ if (defined($_));
    
    $_ = SIRD_PlayPos($name, -1);
    $status{'playPos'} = $_ if (defined($_));
    Log3 $name, 5, $name.' playPos: '.$_ if (defined($_));
    
    $_ = SIRD_Duration($name, -1);
    $status{'duration'} = $_ if (defined($_));
    Log3 $name, 5, $name.' duration: '.$_ if (defined($_));
    
    $_ = SIRD_InfoText($name, -1);
    $status{'infoText'} = $_ if (defined($_));
    Log3 $name, 5, $name.' infoText: '.$_ if (defined($_));
    
    $_ = SIRD_InfoGraphURI($name, -1);
    $status{'infoGraphURI'} = $_ if (defined($_));
    Log3 $name, 5, $name.' infoGraphURI: '.$_ if (defined($_));
    
    $_ = SIRD_SignalStrength($name, -1);
    $status{'signalStrength'} = $_ if (defined($_));
    Log3 $name, 5, $name.' signalStrength: '.$_ if (defined($_));
    
    $_ = SIRD_NavCaps($name, -1);
    $status{'navCaps'} = $_ if (defined($_));
    Log3 $name, 5, $name.' navCaps: '.$_ if (defined($_));
    
    $_ = SIRD_NavNumItems($name, -1);
    $status{'navNumItems'} = $_ if (defined($_));
    Log3 $name, 5, $name.' navNumItems: '.$_ if (defined($_));
    
    $_ = SIRD_PlayCaps($name, -1);
    $status{'playCaps'} = $_ if (defined($_));
    Log3 $name, 5, $name.' playCaps: '.$_ if (defined($_));
    
    $_ = SIRD_VolumeSteps($name, -1);
    $status{'volumeSteps'} = $_ if (defined($_));
    Log3 $name, 5, $name.' volumeSteps: '.$_ if (defined($_));
    
    $_ = SIRD_Time($name, -1);
    $status{'time'} = $_ if (defined($_));
    Log3 $name, 5, $name.' time: '.$_ if (defined($_));
    
    $_ = SIRD_Date($name, -1);
    $status{'date'} = $_ if (defined($_));
    Log3 $name, 5, $name.' date: '.$_ if (defined($_));
    
    $_ = SIRD_SearchTerm($name, -1);
    $status{'searchTerm'} = $_ if (defined($_));
    Log3 $name, 5, $name.' searchTerm: '.$_ if (defined($_));
    
    $_ = SIRD_NavStatus($name, -1);
    $status{'navStatus'} = $_ if (defined($_));
    Log3 $name, 5, $name.' navStatus: '.$_ if (defined($_));
    
    $_ = SIRD_DABScan($name, -1);
    $status{'dabScan'} = $_ if (defined($_));
    Log3 $name, 5, $name.' dabScan: '.$_ if (defined($_));
    
    $_ = SIRD_Frequency($name, -1);
    $status{'frequency'} = $_ if (defined($_));
    Log3 $name, 5, $name.' frequency: '.$_ if (defined($_));
    
    @_ = SIRD_PresetList($name, -1);
    if (scalar(@_) == 4)
    {
      $status{'presetList0'} = $_[0] if (defined($_[0]));
      $status{'presetList1'} = $_[1] if (defined($_[1]));
      $status{'presetList2'} = $_[2] if (defined($_[2]));
      $status{'presetList3'} = $_[3] if (defined($_[3]));
    }

    if ($remoteState ne "on")
    {
      $_ = SIRD_RemoteState($name, "on");
      $status{'remoteState'} = $_ if (defined($_));
      Log3 $name, 5, $name.' remoteState: '.$_ if (defined($_));
    }
  }
  elsif ($_ eq "off")
  {
    $_ = SIRD_Time($name, -1);
    $status{'time'} = $_ if (defined($_));
    Log3 $name, 5, $name.' time: '.$_ if (defined($_));
    
    $_ = SIRD_Date($name, -1);
    $status{'date'} = $_ if (defined($_));
    Log3 $name, 5, $name.' date: '.$_ if (defined($_));
    
    $_ = SIRD_FriendlyName($name, -1);
    $status{'friendlyName'} = $_ if (defined($_));
    Log3 $name, 5, $name.' friendlyName: '.$_ if (defined($_));
    
    $_ = SIRD_Version($name, -1);
    $status{'version'} = $_ if (defined($_));
    Log3 $name, 5, $name.' version: '.$_ if (defined($_));
    
    $_ = SIRD_ID($name, -1);
    $status{'id'} = $_ if (defined($_));
    Log3 $name, 5, $name.' id: '.$_ if (defined($_));
    
    @_ = SIRD_PresetList($name, -1);
    if (scalar(@_) == 4)
    {
      $status{'presetList0'} = $_[0] if (defined($_[0]));
      $status{'presetList1'} = $_[1] if (defined($_[1]));
      $status{'presetList2'} = $_[2] if (defined($_[2]));
      $status{'presetList3'} = $_[3] if (defined($_[3]));
    }
    
    $_ = SIRD_Volume($name, -1);
    $status{'volume'} = $_ if (defined($_));
    Log3 $name, 5, $name.' volume: '.$_ if (defined($_));
  }
  
  return $name.'|'.encode_json(\%status);
}


sub SIRD_EndStatus($)
{
  my ($string) = @_;
  my ($name, $statusEnc) = split("\\|", $string);
  my $hash = $defs{$name};
  my %status = ();

  %status = %{decode_json($statusEnc)} if ('' ne $statusEnc);

  $hash->{STATE} = $status{'power'} if (exists($status{'power'}));
  $hash->{SESSIONID} = $status{'sessionId'} if (exists($status{'sessionId'}));
  $hash->{helper}->{navlist} = $status{'navList'} if (exists($status{'navList'}));
  $hash->{helper}->{preset} = $status{'presetList0'} if (exists($status{'presetList0'}));
  $hash->{helper}->{presetAll} = exists($status{'presetList1'}) ? $status{'presetList1'} : "0";
  $hash->{helper}->{preset1_5} = exists($status{'presetList2'}) ? $status{'presetList2'} : "0";
  $hash->{helper}->{preset6_0} = exists($status{'presetList3'}) ? $status{'presetList3'} : "0";
  $hash->{helper}->{input1} = $status{'input0'} if (exists($status{'input0'}));
  $hash->{helper}->{input2} = $status{'input1'} if (exists($status{'input1'}));
  $hash->{helper}->{inputRead} = exists($status{'input2'}) ? $status{'input2'} : "0";
  $hash->{helper}->{inputAll} = exists($status{'input3'}) ? $status{'input3'} : "0";
    
  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, 'power', exists($status{'power'}) ? $status{'power'} : ' ');
  readingsBulkUpdate($hash, 'presence', (exists($status{'power'}) && $status{'power'} ne 'absent') ? 'present' : 'absent');
  readingsBulkUpdate($hash, 'volumeStraight', exists($status{'volume'}) ? $status{'volume'} : ' ');
  readingsBulkUpdate($hash, 'volume', exists($status{'volume'}) ? $status{'volume'} * 5 : ' ');
  readingsBulkUpdate($hash, 'volumeSteps', exists($status{'volumeSteps'}) ? $status{'volumeSteps'} : ' ');
  readingsBulkUpdate($hash, 'mute', exists($status{'mute'}) ? $status{'mute'} : ' ');
  readingsBulkUpdate($hash, 'shuffle', exists($status{'shuffle'}) ? $status{'shuffle'} : ' ');
  readingsBulkUpdate($hash, 'repeat', exists($status{'repeat'}) ? $status{'repeat'} : ' ');
  readingsBulkUpdate($hash, 'friendlyName', exists($status{'friendlyName'}) ? $status{'friendlyName'} : ' ');
  readingsBulkUpdate($hash, 'version', exists($status{'version'}) ? $status{'version'} : ' ');
  readingsBulkUpdate($hash, 'radioID', exists($status{'id'}) ? $status{'id'} : ' ');
  readingsBulkUpdate($hash, 'localDate', exists($status{'date'}) ? $status{'date'} : ' ');
  readingsBulkUpdate($hash, 'localTime', exists($status{'time'}) ? $status{'time'} : ' ');
  readingsBulkUpdate($hash, 'currentTitle', exists($status{'infoName'}) ? $status{'infoName'} : ' ');
  readingsBulkUpdate($hash, 'infoText', exists($status{'infoText'}) ? $status{'infoText'} : ' ');
  readingsBulkUpdate($hash, 'currentAlbum', exists($status{'infoAlbum'}) ? $status{'infoAlbum'} : ' ');
  readingsBulkUpdate($hash, 'currentArtist', exists($status{'infoArtist'}) ? $status{'infoArtist'} : ' ');
  readingsBulkUpdate($hash, 'graphicUri', exists($status{'infoGraphURI'}) ? $status{'infoGraphURI'} : ' ');
  readingsBulkUpdate($hash, 'currentPosition', exists($status{'playPos'}) ? $status{'playPos'} : ' ');
  readingsBulkUpdate($hash, 'currentDuration', exists($status{'duration'}) ? $status{'duration'} : ' ');
  readingsBulkUpdate($hash, 'playRate', exists($status{'playRate'}) ? $status{'playRate'} : ' ');
  readingsBulkUpdate($hash, 'playCaps', exists($status{'playCaps'}) ? $status{'playCaps'} : ' ');
  readingsBulkUpdate($hash, 'frequency', exists($status{'frequency'}) ? $status{'frequency'} : ' ');
  readingsBulkUpdate($hash, 'signalStrength', exists($status{'signalStrength'}) ? $status{'signalStrength'} : ' ');
  readingsBulkUpdate($hash, 'remoteState', exists($status{'remoteState'}) ? $status{'remoteState'} : ' ');
  readingsBulkUpdate($hash, 'playStatus', exists($status{'playMode'}) ? $status{'playMode'} : ' ');
  readingsBulkUpdate($hash, 'navStatus', exists($status{'navStatus'}) ? $status{'navStatus'} : ' ');
  readingsBulkUpdate($hash, 'navCaps', exists($status{'navCaps'}) ? $status{'navCaps'} : ' ');
  readingsBulkUpdate($hash, 'navNumItems', exists($status{'navNumItems'}) ? $status{'navNumItems'} : ' ');
  readingsBulkUpdate($hash, 'searchTerm', exists($status{'searchTerm'}) ? $status{'searchTerm'} : ' ');
  readingsBulkUpdate($hash, 'dABScan', exists($status{'dabScan'}) ? $status{'dabScan'} : ' ');
  readingsBulkUpdate($hash, 'input', exists($status{'input4'}) ? $status{'input4'} : ' ');
  readingsBulkUpdate($hash, 'inputSelectable', exists($status{'input2'}) ? $status{'input2'} : ' ');
  readingsEndUpdate($hash, 1);

  SIRD_refresh("WEB");  
  
  delete($hash->{helper}{RUNNING_PID});
}


sub SIRD_AbortStatus($)
{
  my ($hash) = @_;
  
  delete($hash->{helper}{RUNNING_PID});
  
  Log3 $hash->{NAME}, 3, 'BlockingCall for '.$hash->{NAME}.' aborted';
}



sub SIRD_Login($)
{
  my ($name) = @_;
  my $response;
  my $xml;

  Log 5, "SIRD try to Login @".InternalVal($name, 'IP', '0');
  
  $response = SIRD_Com($name, "CREATE_SESSION?pin=".InternalVal($name, 'PASSWORD', '1234'), 0, 0, 0);
  
  if (defined($response))
  {
    eval {$xml = XMLin($response, KeyAttr => {}, ForceArray => []);};
    
    if (!$@ && ($xml->{status} eq 'FS_OK')) 
    {
      Log 5, "SIRD Login successful!";
      
      return $xml->{sessionId};
    }
  }
 
  Log 5, "SIRD Login failed!";
   
  return undef;
}


sub SIRD_Power($$)
{
  my ($name, $params) = @_;
  my $response = "";
  my $responseHelper = "false";
  my $ref = "";
  my $refHelper = "false";
  my $helper   = ' ';
  my $presence = 'absent';

  if ( $params eq "on" || $params eq "off" )
  {
    if ( $params eq "on" )
    {
      $helper = '1';
    }
    elsif ( $params eq "off" )
    {
      $helper = '0';
    }
    eval { SIRD_Com( $name, "netRemote.sys.power?pin=", 2, $helper, 0 ); };
    if ($@)
    {
      Log 1, "SIRD Power set error: $@";
      return undef;
    }
    return SIRD_Power( $name, -1 );
  }
  elsif ( $params eq '-1' )
  {
    $response = SIRD_Com( $name, "netRemote.sys.power", 1, 0, 0 );
    $responseHelper = "true" if ! $response || ( $response =~ /fsapiResponse/ );
      my $refXML = eval {
        XMLin( $response, KeyAttr => {}, ForceArray => [] );
      };
      if($@) {
        $responseHelper = "false";
      }
    if ( $responseHelper eq "true" )
    {
      $responseHelper = "false";
      $ref = XMLin( $response, KeyAttr => {}, ForceArray => [] );
      $refHelper = "true" if ! $ref || ( $ref->{status} eq 'FS_OK' );
      ## Überprüfen ob Abfrage in Ordnung war
      if ( $refHelper eq "true" )
      {
        $refHelper = "false";
        if ( $ref->{value}->{u8} == 1 )
        {
          $response = "on";
        }
        else
        {
          $response = "off";
        }
      }
    }
    else
    {
      $response = "absent";
    }

    return $response;
  }
  else
  {
    Log 1, "SIRD Command Power wrong Parameter: " . $params;
  }
  return undef;
}
###############################
sub SIRD_Volume($$);
sub SIRD_Volume($$)
{
  my ( $name, $params ) = @_;
  my $response = "";
  my $responseHelper = "false";
  my $ref;
  my $helper = ' ';

  if ( int($params) >= 0 && int($params) <= 20 )
  {
    eval { SIRD_Com( $name, "netRemote.sys.audio.volume", 2, $params, 0 ); };
    if ($@)
    {
      ### catch block
      Log 1, "SIRD Volume set error: $@";
      return undef;
    }
    return SIRD_Volume( $name, -1 );
  }
  elsif ( $params eq '-1' )
  {
    $response = SIRD_Com( $name, "netRemote.sys.audio.volume", 1, 0, 0 );
#    if ($response eq "exit") {
#      exit 1;
#    }
    ## Überprüfen ob Abfrage in Ordnung war
    $responseHelper = "true" if ! $response || ( $response =~ /fsapiResponse/ );
      my $refXML = eval {
        XMLin( $response, KeyAttr => {}, ForceArray => [] );
      };
      if($@) {
        $responseHelper = "false";
#Log 1, "Volume: XML-Error: ".$@;
      }
    if ( $responseHelper eq "true" )
    {
      $responseHelper = "false";
      $ref = XMLin( $response, KeyAttr => {}, ForceArray => [] );
      if ( $ref->{status} eq 'FS_OK' )
      {
        return int($ref->{value}->{u8});
      }
    }
  }
  else
  {
    Log 1, "SIRD Command Volume Parameter: " . $params;
  }
  return undef;
}
###############################
sub SIRD_VolumeSteps($$);
sub SIRD_VolumeSteps($$)
{
  my ( $name, $params ) = @_;
  my $response = "";
  my $responseHelper = "false";
  my $ref;
  my $helper = ' ';
  ##########################################
  # read only
  ##########################################
  if ( $params eq '-1' )
  {
    $response = SIRD_Com( $name, "netRemote.sys.caps.volumeSteps", 1, 0, 0 );
    ## Überprüfen ob Abfrage in Ordnung war
    $responseHelper = "true" if ! $response || ( $response =~ /fsapiResponse/ );
      my $refXML = eval {
        XMLin( $response, KeyAttr => {}, ForceArray => [] );
      };
      if($@) {
        $responseHelper = "false";
#Log 1, "VolumeSteps: XML-Error: ".$@;
      }
    if ( $responseHelper eq "true" )
    {
      $responseHelper = "false";
      $ref = XMLin( $response, KeyAttr => {}, ForceArray => [] );
      if ( $ref->{status} eq 'FS_OK' )
      {
        return $ref->{value}->{u8};
      }
    }
  }
  else
  {
    Log 1, "SIRD Command VolumeSteps wrong Parameter: " . $params;
  }
  return undef;
}
###############################
sub SIRD_Mute($$);
sub SIRD_Mute($$)
{
  my ( $name, $params ) = @_;
  my $response = "";
  my $responseHelper = "false";
  my $ref;
  my $helper = ' ';

  if ( $params eq "on" || $params eq "off" )
  {
    if ( $params eq "on" )
    {
      $helper = '1';
    }
    elsif ( $params eq "off" )
    {
      $helper = '0';
    }
    eval { SIRD_Com( $name, "netRemote.sys.audio.mute", 2, $helper, 0 ); };
    if ($@)
    {
      ### catch block
      Log 1, "SIRD Mute set error: $@";
      return undef;
    }
    return SIRD_Mute( $name, -1 );
  }
  elsif ( $params eq '-1' )
  {
    $response = SIRD_Com( $name, "netRemote.sys.audio.mute", 1, 0, 0 );
    $responseHelper = "true" if ! $response || ( $response =~ /fsapiResponse/ );
      my $refXML = eval {
        XMLin( $response, KeyAttr => {}, ForceArray => [] );
      };
      if($@) {
        $responseHelper = "false";
#Log 1, "Mute: XML-Error: ".$@;
      }
    if ( $responseHelper eq "true" )
    {
      $responseHelper = "false";
      ## Überprüfen ob Abfrage in Ordnung war
      $ref = XMLin( $response, KeyAttr => {}, ForceArray => [] );
      if ( $ref->{status} eq 'FS_OK' )
      {
        if ( $ref->{value}->{u8} == 1 )
        {
          return "on";
        }
        else
        {
          return "off";
        }
      }
    }
  }
  else
  {
    Log 1, "SIRD Command Mute wrong Parameter: " . $params;
  }
  return undef;
}
###############################
sub SIRD_Shuffle($$);
sub SIRD_Shuffle($$)
{
  my ( $name, $params ) = @_;
  my $response = "";
  my $responseHelper = "false";
  my $ref;
  my $helper = ' ';

  if ( $params eq "on" || $params eq "off" )
  {
    if ( $params eq "on" )
    {
      $helper = '1';
    }
    elsif ( $params eq "off" )
    {
      $helper = '0';
    }
    eval { SIRD_Com( $name, "netRemote.play.shuffle", 2, $helper, 0 ); };
    if ($@)
    {
      ### catch block
      Log 1, "SIRD Shuffle set error: $@";
      return undef;
    }
    return SIRD_Shuffle( $name, -1 );
  }
  elsif ( $params eq '-1' )
  {
    $response = SIRD_Com( $name, "netRemote.play.shuffle", 1, 0, 0 );
    $responseHelper = "true" if ! $response || ( $response =~ /fsapiResponse/ );
      my $refXML = eval {
        XMLin( $response, KeyAttr => {}, ForceArray => [] );
      };
      if($@) {
        $responseHelper = "false";
#Log 1, "Shuffle: XML-Error: ".$@;
      }
    if ( $responseHelper eq "true" )
    {
      $responseHelper = "false";
      $ref = XMLin( $response, KeyAttr => {}, ForceArray => [] );
      ## Überprüfen ob Abfrage in Ordnung war
      if ( $ref->{status} eq 'FS_OK' )
      {
        if ( $ref->{value}->{u8} == 1 )
        {
          return "on";
        }
        else
        {
          return "off";
        }
      }
    }
  }
  else
  {
    Log 1, "SIRD Command Shuffle wrong Parameter: " . $params;
  }
  return undef;
}
###############################
sub SIRD_Repeat($$);
sub SIRD_Repeat($$)
{
  my ( $name, $params ) = @_;
  my $response = "";
  my $responseHelper = "false";
  my $ref;
  my $helper = ' ';

  if ( $params eq "on" || $params eq "off" )
  {
    if ( $params eq "on" )
    {
      $helper = '1';
    }
    elsif ( $params eq "off" )
    {
      $helper = '0';
    }
    eval { SIRD_Com( $name, "netRemote.play.repeat", 2, $helper, 0 ); };
    if ($@)
    {
      ### catch block
      Log 1, "SIRD Repeat set error: $@";
      return undef;
    }
    return SIRD_Repeat( $name, -1 );
  }
  elsif ( $params eq '-1' )
  {
    $response = SIRD_Com( $name, "netRemote.play.shuffle", 1, 0, 0 );
    $responseHelper = "true" if ! $response || ( $response =~ /fsapiResponse/ );
      my $refXML = eval {
        XMLin( $response, KeyAttr => {}, ForceArray => [] );
      };
      if($@) {
        $responseHelper = "false";
#Log 1, "Repeat: XML-Error: ".$@;
      }
    if ( $responseHelper eq "true" )
    {
      $responseHelper = "false";
      $ref = XMLin( $response, KeyAttr => {}, ForceArray => [] );
      ## Überprüfen ob Abfrage in Ordnung war
      if ( $ref->{status} eq 'FS_OK' )
      {
        if ( $ref->{value}->{u8} == 1 )
        {
          return "on";
        }
        else
        {
          return "off";
        }
      }
    }
  }
  else
  {
    Log 1, "SIRD Command Repeat wrong Parameter: " . $params;
  }
  return undef;
}
###############################
sub SIRD_FriendlyName($$);
sub SIRD_FriendlyName($$)
{
  my ( $name, $params ) = @_;
  my $response = "";
  my $responseHelper = "false";
  my $ref;
  my $helper = ' ';
  ##########################################
  # read only
  ##########################################
  if ( $params eq '-1' )
  {
    $response = SIRD_Com( $name, "netRemote.sys.info.friendlyName", 1, 0, 0 );
    $responseHelper = "true" if ! $response || ( $response =~ /fsapiResponse/ );
      my $refXML = eval {
        XMLin( $response, KeyAttr => {}, ForceArray => [] );
      };
      if($@) {
        $responseHelper = "false";
#Log 1, "FriendlyName: XML-Error: ".$@;
      }
    if ( $responseHelper eq "true" )
    {
      $responseHelper = "false";
      $ref = XMLin( $response, KeyAttr => {}, ForceArray => [] );
      ## Überprüfen ob Abfrage in Ordnung war
      if ( $ref->{status} eq 'FS_OK' )
      {
        if ( !ref($ref->{value}->{c8_array}) )
        {
          return encode_utf8( SIRD_xml2txt( $ref->{value}->{c8_array} ) );
        }
      }
    }
  }
  else
  {
    Log 1, "SIRD Command FriendlyName wrong Parameter: " . $params;
  }
  return undef;
}
###############################
sub SIRD_Version($$);
sub SIRD_Version($$)
{
  my ( $name, $params ) = @_;
  my $response = "";
  my $responseHelper = "false";
  my $ref;
  my $helper = ' ';
  ##########################################
  # read only
  ##########################################
  if ( $params eq '-1' )
  {
    $response = SIRD_Com( $name, "netRemote.sys.info.version", 1, 0, 0 );
    $responseHelper = "true" if ! $response || ( $response =~ /fsapiResponse/ );
      my $refXML = eval {
        XMLin( $response, KeyAttr => {}, ForceArray => [] );
      };
      if($@) {
        $responseHelper = "false";
#Log 1, "Version: XML-Error: ".$@;
      }
    if ( $responseHelper eq "true" )
    {
      $responseHelper = "false";
      $ref = XMLin( $response, KeyAttr => {}, ForceArray => [] );
      ## Überprüfen ob Abfrage in Ordnung war
      if ( $ref->{status} eq 'FS_OK' )
      {
        if ( !ref $ref->{value}->{c8_array} )
        {
          return encode_utf8( SIRD_xml2txt( $ref->{value}->{c8_array} ) );
        }
      }
    }
  }
  else
  {
    Log 1, "SIRD Command Version wrong Parameter: " . $params;
  }
  return undef;
}
###############################
sub SIRD_ID($$);
sub SIRD_ID($$)
{
  my ( $name, $params ) = @_;
  my $response = "";
  my $responseHelper = "false";
  my $ref;
  my $helper = ' ';
  ##########################################
  # read only
  ##########################################
  if ( $params eq '-1' )
  {
    $response = SIRD_Com( $name, "netRemote.sys.info.radioID", 1, 0, 0 );
    $responseHelper = "true" if ! $response || ( $response =~ /fsapiResponse/ );
      my $refXML = eval {
        XMLin( $response, KeyAttr => {}, ForceArray => [] );
      };
      if($@) {
        $responseHelper = "false";
#Log 1, "ID: XML-Error: ".$@;
      }
    if ( $responseHelper eq "true" )
    {
      $responseHelper = "false";
      $ref = XMLin( $response, KeyAttr => {}, ForceArray => [] );
      ## Überprüfen ob Abfrage in Ordnung war
      if ( $ref->{status} eq 'FS_OK' )
      {
        if ( !ref $ref->{value}->{c8_array} )
        {
          return encode_utf8( SIRD_xml2txt( $ref->{value}->{c8_array} ) );
        }
      }
    }
  }
  else
  {
    Log 1, "SIRD Command ID wrong Parameter: " . $params;
  }
  return undef;
}
###############################
sub SIRD_Date($$);
sub SIRD_Date($$)
{
  my ( $name, $params ) = @_;
  my $response = "";
  my $responseHelper = "false";
  my $ref;
  my $helper = ' ';
  ##########################################
  # read only at the Moment
  ##########################################
  if ( $params eq '-1' )
  {
    $response = SIRD_Com( $name, "netRemote.sys.clock.localDate", 1, 0, 0 );
    $responseHelper = "true" if ! $response || ( $response =~ /fsapiResponse/ );
      my $refXML = eval {
        XMLin( $response, KeyAttr => {}, ForceArray => [] );
      };
      if($@) {
        $responseHelper = "false";
#Log 1, "Date: XML-Error: ".$@;
      }
    if ( $responseHelper eq "true" )
    {
      $responseHelper = "false";
      $ref = XMLin( $response, KeyAttr => {}, ForceArray => [] );
      ## Überprüfen ob Abfrage in Ordnung war
      if ( $ref->{status} eq 'FS_OK' )
      {
        if ( !ref $ref->{value}->{c8_array} )
        {
          return encode_utf8(
                           SIRD_xml2txt(
                                 substr( $ref->{value}->{c8_array}, 6, 2 ) . "."
                               . substr( $ref->{value}->{c8_array}, 4, 2 ) . "."
                               . substr( $ref->{value}->{c8_array}, 0, 4 )
                           ));
        }
      }
    }
  }
  else
  {
    Log 1, "SIRD Command Date wrong Parameter: " . $params;
  }
  return undef;
}
###############################
sub SIRD_Time($$);
sub SIRD_Time($$)
{
  my ( $name, $params ) = @_;
  my $response = "";
  my $responseHelper = "false";
  my $ref;
  my $helper = ' ';
  ##########################################
  # read only at the Moment
  ##########################################
  if ( $params eq '-1' )
  {
    $response = SIRD_Com( $name, "netRemote.sys.clock.localTime", 1, 0, 0 );
    $responseHelper = "true" if ! $response || ( $response =~ /fsapiResponse/ );
      my $refXML = eval {
        XMLin( $response, KeyAttr => {}, ForceArray => [] );
      };
      if($@) {
        $responseHelper = "false";
#        Log 1, "Time: XML-Error: ".$@;
      }
    if ( $responseHelper eq "true" )
    {
      $responseHelper = "false";
      $ref = XMLin( $response, KeyAttr => {}, ForceArray => [] );
      ## Überprüfen ob Abfrage in Ordnung war
      if ( $ref->{status} eq 'FS_OK' )
      {
        if ( !ref $ref->{value}->{c8_array} )
        {
          return encode_utf8(
                           SIRD_xml2txt(
                                 substr( $ref->{value}->{c8_array}, 0, 2 ) . ":"
                               . substr( $ref->{value}->{c8_array}, 2, 2 ) . ":"
                               . substr( $ref->{value}->{c8_array}, 4, 2 )
                           ));
        }
      }
    }
  }
  else
  {
    Log 1, "SIRD Command Time wrong Parameter: " . $params;
  }
  return undef;
}
###############################
sub SIRD_InfoName($$);
sub SIRD_InfoName($$)
{
  my ( $name, $params ) = @_;
  my $response = "";
  my $responseHelper = "false";
  my $ref;
  my $helper = ' ';
  ##########################################
  # read only
  ##########################################
  if ( $params eq '-1' )
  {
    $response = SIRD_Com( $name, "netRemote.play.info.name", 1, 0, 0 );
    $responseHelper = "true" if ! $response || ( $response =~ /fsapiResponse/ );
      my $refXML = eval {
        XMLin( $response, KeyAttr => {}, ForceArray => [] );
      };
      if($@) {
        $responseHelper = "false";
#Log 1, "InfoName: XML-Error: ".$@;
      }
    if ( $responseHelper eq "true" )
    {
      $responseHelper = "false";
      $ref = XMLin( $response, KeyAttr => {}, ForceArray => [] );
      ## Überprüfen ob Abfrage in Ordnung war
      if ( $ref->{status} eq 'FS_OK' )
      {
        if ( !ref $ref->{value}->{c8_array} )
        {
          return encode_utf8( SIRD_xml2txt( $ref->{value}->{c8_array} ) );
        }
      }
    }
  }
  else
  {
    Log 1, "SIRD Command InfoName wrong Parameter: " . $params;
  }
  return undef;
}
###############################
sub SIRD_InfoText($$);
sub SIRD_InfoText($$)
{
  my ( $name, $params ) = @_;
  my $response = "";
  my $responseHelper = "false";
  my $ref;
  my $helper = ' ';
  ##########################################
  # read only
  ##########################################
  if ( $params eq '-1' )
  {
    $response = SIRD_Com( $name, "netRemote.play.info.text", 1, 0, 0 );
    $responseHelper = "true" if ! $response || ( $response =~ /fsapiResponse/ );
      my $refXML = eval {
        XMLin( $response, KeyAttr => {}, ForceArray => [] );
      };
      if($@) {
        $responseHelper = "false";
#Log 1, "InfoText: XML-Error: ".$@;
      }
    if ( $responseHelper eq "true" )
    {
      $responseHelper = "false";
      $ref = XMLin( $response, KeyAttr => {}, ForceArray => [] );
      ## Überprüfen ob Abfrage in Ordnung war
      if ( $ref->{status} eq 'FS_OK' )
      {
        if ( !ref $ref->{value}->{c8_array} )
        {
          return encode_utf8( SIRD_xml2txt( $ref->{value}->{c8_array} ) );
        }
      }
    }
  }
  else
  {
    Log 1, "SIRD Command InfoText wrong Parameter: " . $params;
  }
  return undef;
}
###############################
sub SIRD_InfoAlbum($$);
sub SIRD_InfoAlbum($$)
{
  my ( $name, $params ) = @_;
  my $response = "";
  my $responseHelper = "false";
  my $ref;
  my $helper = ' ';
  ##########################################
  # read only at the Moment
  ##########################################
  if ( $params eq '-1' )
  {
    $response = SIRD_Com( $name, "netRemote.play.info.album", 1, 0, 0 );
    $responseHelper = "true" if ! $response || ( $response =~ /fsapiResponse/ );
      my $refXML = eval {
        XMLin( $response, KeyAttr => {}, ForceArray => [] );
      };
      if($@) {
        $responseHelper = "false";
#Log 1, "InfoAlbum: XML-Error: ".$@;
      }
    if ( $responseHelper eq "true" )
    {
      $responseHelper = "false";
      $ref = XMLin( $response, KeyAttr => {}, ForceArray => [] );
      ## Überprüfen ob Abfrage in Ordnung war
      if ( $ref->{status} eq 'FS_OK' )
      {
        if ( !ref $ref->{value}->{c8_array} )
        {
          return encode_utf8( SIRD_xml2txt( $ref->{value}->{c8_array} ) );
        }
      }
    }
  }
  else
  {
    Log 1, "SIRD Command InfoAlbum wrong Parameter: " . $params;
  }
  return undef;
}
###############################
sub SIRD_InfoArtist($$);
sub SIRD_InfoArtist($$)
{
  my ( $name, $params ) = @_;
  my $response = "";
  my $responseHelper = "false";
  my $ref;
  my $helper = ' ';
  ##########################################
  # read only
  ##########################################
  if ( $params eq '-1' )
  {
    $response = SIRD_Com( $name, "netRemote.play.info.artist", 1, 0, 0 );
    $responseHelper = "true" if ! $response || ( $response =~ /fsapiResponse/ );
      my $refXML = eval {
        XMLin( $response, KeyAttr => {}, ForceArray => [] );
      };
      if($@) {
        $responseHelper = "false";
#Log 1, "InfoArtist: XML-Error: ".$@;
      }
    if ( $responseHelper eq "true" )
    {
      $responseHelper = "false";
      $ref = XMLin( $response, KeyAttr => {}, ForceArray => [] );
      ## Überprüfen ob Abfrage in Ordnung war
      if ( $ref->{status} eq 'FS_OK' )
      {
        if ( !ref $ref->{value}->{c8_array} )
        {
          return encode_utf8( SIRD_xml2txt( $ref->{value}->{c8_array} ) );
        }
      }
    }
  }
  else
  {
    Log 1, "SIRD Command InfoArtist wrong Parameter: " . $params;
  }
  return undef;
}
##############################
sub SIRD_InfoGraphURI($$);
sub SIRD_InfoGraphURI($$)
{
  my ( $name, $params ) = @_;
  my $response = "";
  my $responseHelper = "false";
  my $ref;
  my $helper = ' ';
  ##########################################
  # read only
  ##########################################
  if ( $params eq '-1' )
  {
    $response = SIRD_Com( $name, "netRemote.play.info.graphicUri", 1, 0, 0 );
    $responseHelper = "true" if ! $response || ( $response =~ /fsapiResponse/ );
      my $refXML = eval {
        XMLin( $response, KeyAttr => {}, ForceArray => [] );
      };
      if($@) {
        $responseHelper = "false";
#Log 1, "InfoGraphURI: XML-Error: ".$@;
      }
    if ( $responseHelper eq "true" )
    {
      $responseHelper = "false";
      $ref = XMLin( $response, KeyAttr => {}, ForceArray => [] );
      ## Überprüfen ob Abfrage in Ordnung war
      if ( $ref->{status} eq 'FS_OK' )
      {
        if ( !ref $ref->{value}->{c8_array} )
        {
          return encode_utf8( SIRD_xml2txt( $ref->{value}->{c8_array} ) );
        }
      }
    }
  }
  else
  {
    Log 1, "SIRD Command InfoGraphURI wrong Parameter: " . $params;
  }
  return undef;
}
##############################
sub SIRD_PlayPos($$);
sub SIRD_PlayPos($$)
{
  my ( $name, $params ) = @_;
  my $response = "";
  my $responseHelper = "false";
  my $ref;
  my $helper = ' ';
  ##########################################
  # read only
  ##########################################
  if ( $params eq '-1' )
  {
    $response = SIRD_Com( $name, "netRemote.play.position", 1, 0, 0 );
    $responseHelper = "true" if ! $response || ( $response =~ /fsapiResponse/ );
      my $refXML = eval {
        XMLin( $response, KeyAttr => {}, ForceArray => [] );
      };
      if($@) {
        $responseHelper = "false";
#Log 1, "PlayPos: XML-Error: ".$@;
      }
    if ( $responseHelper eq "true" )
    {
      $responseHelper = "false";
      $ref = XMLin( $response, KeyAttr => {}, ForceArray => [] );
      ## Überprüfen ob Abfrage in Ordnung war
      if ( $ref->{status} eq 'FS_OK' )
      {

        #Zeit von 1000stel Sekunden in Minuten umwandeln xx:yy
        return encode_utf8(
                            SIRD_xml2txt(
                                  " " 
                                . int( $ref->{value}->{u32} / 60000 ) . ":"
                                . sprintf(
                                "%02d",
                                (
                                  int( $ref->{value}->{u32} / 1000 ) -
                                    ( int( $ref->{value}->{u32} / 60000 ) * 60 )
                                )
                                )
                            )
        );
      }
    }
  }
  else
  {
    Log 1, "SIRD Command PlayPos wrong Parameter: " . $params;
  }
  return undef;
}
##############################
sub SIRD_Duration($$);
sub SIRD_Duration($$)
{
  my ( $name, $params ) = @_;
  my $response = "";
  my $responseHelper = "false";
  my $ref;
  my $helper = ' ';
  ##########################################
  # read only
  ##########################################
  if ( $params eq '-1' )
  {
    $response = SIRD_Com( $name, "netRemote.play.info.duration", 1, 0, 0 );
    $responseHelper = "true" if ! $response || ( $response =~ /fsapiResponse/ );
      my $refXML = eval {
        XMLin( $response, KeyAttr => {}, ForceArray => [] );
      };
      if($@) {
        $responseHelper = "false";
#Log 1, "Duration: XML-Error: ".$@;
      }
    if ( $responseHelper eq "true" )
    {
      $responseHelper = "false";
      $ref = XMLin( $response, KeyAttr => {}, ForceArray => [] );
      ## Überprüfen ob Abfrage in Ordnung war
      if ( $ref->{status} eq 'FS_OK' )
      {

        #Zeit von 1000stel Sekunden in Minuten umwandeln xx:yy
        return encode_utf8(
                            SIRD_xml2txt(
                                  " " 
                                . int( $ref->{value}->{u32} / 60000 ) . ":"
                                . sprintf(
                                "%02d",
                                (
                                  int( $ref->{value}->{u32} / 1000 ) -
                                    ( int( $ref->{value}->{u32} / 60000 ) * 60 )
                                )
                                )
                            )
        );
      }
    }
  }
  else
  {
    Log 1, "SIRD Command Duration wrong Parameter: " . $params;
  }
  return undef;
}
###############################
sub SIRD_PlayRate($$);
sub SIRD_PlayRate($$)
{
  my ( $name, $params ) = @_;
  my $response = "";
  my $responseHelper = "false";
  my $ref = "";
  my $refHelper = "false";
  my $helper = ' ';
  my $helperH = "false";
  ##########################################
  # read only at the moment
  ##########################################(jb)
  if ( $params eq '-1' )
  {
    $response = SIRD_Com( $name, "netRemote.play.rate", 1, 0, 0 );
###    Log 1, "Playrate Response: ".$response;
    $responseHelper = "true" if ! $response || ( $response =~ /fsapiResponse/ );
      my $refXML = eval {
        XMLin( $response, KeyAttr => {}, ForceArray => [] );
      };
      if($@) {
        $responseHelper = "false";
#Log 1, "PlayRate: XML-Error: ".$@;
      }
    if ( $responseHelper eq "true" )
    {
      $responseHelper = "false";
      $ref = XMLin( $response, KeyAttr => {}, ForceArray => [] );
      $refHelper = "true" if ! $ref || ( $ref->{status} eq "FS_OK" );
      ## Überprüfen ob Abfrage in Ordnung war
      if ( $refHelper eq "true" )
      {
          return encode_utf8( sprintf "%s", ( $ref->{value}->{s8} ) );
      }
    }
  }
  else
  {
    Log 1, "SIRD Command PlayRate wrong Parameter: " . $params;
  }
  return undef;
}
###############################
sub SIRD_PlayCaps($$);
sub SIRD_PlayCaps($$)
{
  my ( $name, $params ) = @_;
  my $response = "";
  my $responseHelper = "false";
  my $ref;
  my $helper = "";
  ##########################################
  # read only
  ##########################################
  if ( $params eq '-1' )
  {
    $response = SIRD_Com( $name, "netRemote.play.caps", 1, 0, 0 );
    $responseHelper = "true" if ! $response || ( $response =~ /fsapiResponse/ );
      my $refXML = eval {
        XMLin( $response, KeyAttr => {}, ForceArray => [] );
      };
      if($@) {
        $responseHelper = "false";
#Log 1, "PlayCaps: XML-Error: ".$@;
      }
    if ( $responseHelper eq "true" )
    {
      $responseHelper = "false";
      $ref = XMLin( $response, KeyAttr => {}, ForceArray => [] );
      ## Überprüfen ob Abfrage in Ordnung war
      if ( $ref->{status} eq 'FS_OK' )

      {
        if ( ( int( $ref->{value}->{u32} ) & 1 ) > 0 )
        {
          $helper = $helper . "pause,";
        }
        if ( ( int( $ref->{value}->{u32} ) & 2 ) > 0 )
        {
          $helper = $helper . "stop,";
        }
        if ( ( int( $ref->{value}->{u32} ) & 4 ) > 0 )
        {
          $helper = $helper . "skipNext,";
        }
        if ( ( int( $ref->{value}->{u32} ) & 8 ) > 0 )
        {
          $helper = $helper . "skipPrevious,";
        }
        if ( ( int( $ref->{value}->{u32} ) & 16 ) > 0 )
        {
          $helper = $helper . "fastForward,";
        }
        if ( ( int( $ref->{value}->{u32} ) & 32 ) > 0 )
        {
          $helper = $helper . "rewind,";
        }
        if ( ( int( $ref->{value}->{u32} ) & 64 ) > 0 )
        {
          $helper = $helper . "shuffle,";
        }
        if ( ( int( $ref->{value}->{u32} ) & 128 ) > 0 )
        {
          $helper = $helper . "repeat,";
        }
        if ( ( int( $ref->{value}->{u32} ) & 256 ) > 0 )
        {
          $helper = $helper . "seek,";
        }
        if ( ( int( $ref->{value}->{u32} ) & 512 ) > 0 )
        {
          $helper = $helper . "applyFeedback,";
        }
        if ( ( int( $ref->{value}->{u32} ) & 1024 ) > 0 )
        {
          $helper = $helper . "scrobbling,";
        }
        if ( ( int( $ref->{value}->{u32} ) & 2048 ) > 0 )
        {
          $helper = $helper . "addPreset,";
        }
        chop($helper);
        return encode_utf8($helper);
      }
    }
  }
  else
  {
    Log 1, "SIRD Command PlayCaps wrong Parameter: " . $params;
  }
  return undef;
}
###############################
sub SIRD_Frequency($$);
sub SIRD_Frequency($$)
{
  my ( $name, $params ) = @_;
  my $response = "";
  my $responseHelper = "false";
  my $ref;
  my $helper = ' ';
  ##########################################
  # read only
  ##########################################
  if ( $params eq '-1' )
  {
    $response = SIRD_Com( $name, "netRemote.play.frequency", 1, 0, 0 );
    $responseHelper = "true" if ! $response || ( $response =~ /fsapiResponse/ );
      my $refXML = eval {
        XMLin( $response, KeyAttr => {}, ForceArray => [] );
      };
      if($@) {
        $responseHelper = "false";
#Log 1, "Frequency: XML-Error: ".$@;
      }
    if ( $responseHelper eq "true" )
    {
      $responseHelper = "false";
      $ref = XMLin( $response, KeyAttr => {}, ForceArray => [] );
      ## Überprüfen ob Abfrage in Ordnung war
      if ( $ref->{status} eq 'FS_OK' )
      {
        return encode_utf8( sprintf( "%.2f", ( $ref->{value}->{u32} / 1000 ) ) );
      }
    }
  }
  else
  {
    Log 1, "SIRD Command Frequency wrong Parameter: " . $params;
  }
  return undef;
}
###############################
sub SIRD_SignalStrength($$);
sub SIRD_SignalStrength($$)
{
  my ( $name, $params ) = @_;
  my $response = "";
  my $responseHelper = "false";
  my $ref;
  my $helper = ' ';
  ##########################################
  # read only
  ##########################################
  if ( $params eq '-1' )
  {
    $response = SIRD_Com( $name, "netRemote.play.signalStrength", 1, 0, 0 );
    $responseHelper = "true" if ! $response || ( $response =~ /fsapiResponse/ );
      my $refXML = eval {
        XMLin( $response, KeyAttr => {}, ForceArray => [] );
      };
      if($@) {
        $responseHelper = "false";
#Log 1, "SignalStrength: XML-Error: ".$@;
      }
    if ( $responseHelper eq "true" )
    {
      $responseHelper = "false";
      $ref = XMLin( $response, KeyAttr => {}, ForceArray => [] );
      ## Überprüfen ob Abfrage in Ordnung war
      if ( $ref->{status} eq 'FS_OK' )
      {
        return encode_utf8( sprintf "%s", ( $ref->{value}->{u8} ) );
      }
    }
  }
  else
  {
    Log 1, "SIRD Command signalStrength wrong Parameter: " . $params;
  }
  return undef;
}
###############################
sub SIRD_RemoteState($$);
sub SIRD_RemoteState($$)
{
  my ( $name, $params ) = @_;
  my $response = "";
  my $responseHelper = "false";
  my $ref;
  my $helper = ' ';

  if ( $params eq "on" || $params eq "off" )
  {
    if ( $params eq "on" )
    {
      $helper = '1';
    }
    elsif ( $params eq "off" )
    {
      $helper = '0';
    }
    eval { SIRD_Com( $name, "netRemote.nav.state", 2, $helper, 0 ); };
    if ($@)
    {
      ### catch block
      Log 1, "SIRD RemoteState set error: $@";
      return undef;
    }
    return SIRD_RemoteState( $name, -1 );
  }
  elsif ( $params eq '-1' )
  {
    $response = SIRD_Com( $name, "netRemote.nav.state", 1, 0, 0 );
    $responseHelper = "true" if ! $response || ( $response =~ /fsapiResponse/ );
      my $refXML = eval {
        XMLin( $response, KeyAttr => {}, ForceArray => [] );
      };
      if($@) {
        $responseHelper = "false";
#Log 1, "RemoteState: XML-Error: ".$@;
      }
    if ( $responseHelper eq "true" )
    {
      $responseHelper = "false";
      $ref = XMLin( $response, KeyAttr => {}, ForceArray => [] );
      ## Überprüfen ob Abfrage in Ordnung war
      if ( $ref->{status} eq 'FS_OK' )
      {
        if ( $ref->{value}->{u8} == 1 )
        {
          return "on";
        }
        else
        {
          return "off";
        }
      }
    }
  }
  else
  {
    Log 1, "SIRD Command RemoteState wrong Parameter: " . $params;
  }
  return undef;
}
###############################
sub SIRD_Input($$);
sub SIRD_Input($$)
{

  #  cachable
  #  notifying
  my ( $name, $params ) = @_;
  my $response = "";
  my $refXMLinput = "";
  my $responseHelper = "false";
  my $ref;
  my $ref2;
  my $helper = ' ';
  my $helper2 = "";

#    if ( $params ne '-1' ) {
#      if ($hash->{Model} eq "SIRD-AUTOMATIC" ) {
#        if ( defined( $hash->{helper}->{inputAll} )) {
#          if ( $hash->{helper}->{inputAll} ne "0" ) {
#            my $idxInput = '0';
#            my @valIn = split(',', $hash->{helper}->{inputAll});
#              foreach my $valIn1 (@valIn) {
#              if ($params eq $valIn1) {
#                $helper = $idxInput;
#                $helper2 = $valIn1;
#              }
#              $idxInput++;
#            }
#            $idxInput = '0';
#          }
#        }
#      }
#    }

  if ( $params ne '-1' ) {
    eval { SIRD_Com( $name, "netRemote.sys.mode", 2, $params, 0 ); };
    if ($@)
    {
      ### catch block
      Log 1, "SIRD Input set error: $@";
      return undef;
    }
    return SIRD_Input( $name, -1 );
  }
  else {
#        if ($hash->{Model} eq "SIRD-AUTOMATIC" ) {
          $response = SIRD_Com( $name, "netRemote.sys.mode", 1, 0, 0 );
          my $response2 = SIRD_Com( $name, "netRemote.sys.caps.validModes/-1", 4, 0, 100 );
          $responseHelper = "true" if ! $response || ( $response =~ /fsapiResponse/ );
          my $refXML = eval {
            XMLin( $response, KeyAttr => {}, ForceArray => [] );
          };
          if($@) {
            $responseHelper = "false";
          }
          if ( $responseHelper eq "true" )
          {
            my $responseXMLinput = "";
            my $listpos1 = '0';
            my $listpos2 = '0';
            my $listNamePos1 = '0';
            my $listNamePos2 = '0';
            my $listName2 = "";
            my $listName3 = "";
            my $idxInput = '0';
            my $substr1 = '0';
            my $substr2 = '0';
            my $substr3 = '0';
            my $substr4 = '0';

            $responseHelper = "false";
            $ref = XMLin( $response, KeyAttr => {}, ForceArray => [] );
            $ref2 = XMLin( $response2, KeyAttr => {}, ForceArray => [] );
            ## Überprüfen ob Abfrage in Ordnung war
            if ( $ref->{status} eq 'FS_OK' && $ref2->{status} eq 'FS_OK' )
            {
              $responseXMLinput = $response2;
#Log 1, "ResponseXMLinput: ".$responseXMLinput;              
              if ( defined( $ref )
              && defined( $response2 )
              && ref( $ref->{value} ) eq "HASH" )
              {
                if ( $ref->{'status'} eq "FS_OK" )
                {
                  $responseXMLinput  = $response2;
                  if ($responseXMLinput =~ /streamable/) {
                    $substr1 = '0';
                    $substr2 = '31';
                    $substr3 = '0';
                    $substr4 = '43';
                  }
                  else {
                    $substr1 = '0';
                    $substr2 = '31';
                    $substr3 = '0';
                    $substr4 = '21';
                  }
                  while ($responseXMLinput =~ /table"><u8>|labe|l"><c8_array>|streamable|<\/c8_array><\/field>\n\n/g) {
                    if ( $listpos1 eq '0' && $listpos2 eq '0' && $listNamePos1 eq '0' && $listNamePos2 eq '0' ) {
                      $listpos1 = pos ($responseXMLinput) + $substr1;
                    }
                    elsif ( $listpos1 ne '0' && $listpos2 eq '0' && $listNamePos1 eq '0' && $listNamePos2 eq '0'  ) {
                      $listpos2 = pos ($responseXMLinput) - $substr2;
                    }
                    elsif ( $listpos1 ne '0' && $listpos2 ne '0' && $listNamePos1 eq '0' && $listNamePos2 eq '0'  ) {
                      $listNamePos1 = pos ($responseXMLinput) + $substr3;
                    }
                    elsif ( $listpos1 ne '0' && $listpos2 ne '0' && $listNamePos1 ne '0' && $listNamePos2 eq '0'  ) {
                      $listNamePos2 = pos ($responseXMLinput) - $substr4;
                    }
                    if ( $listpos1 ne '0' && $listpos2 ne '0' && $listNamePos1 ne '0' && $listNamePos2 ne '0'  ) {
                      my $listpos3 = $listpos2 - $listpos1;
                      my $listNamePos3 = $listNamePos2 - $listNamePos1;
                      my $select1 = substr($responseXMLinput,$listpos1,$listpos3);
                      my $listName1 = substr($responseXMLinput,$listNamePos1,$listNamePos3);
                      $listName1 = SIRD_space2sub ($listName1);
                      if ($select1 == '1' ) {
                        $listName2 .= "<".$listName1.">";
                      }
                      if ( $listName3 ne "" && $select1 == '1') {
                        $listName3 .= ",";
                      }
                      if ($select1 == '1' ) {
                        $listName3 .= $listName1;
                      }
                      $listpos1 = '0';
                      $listpos2 = '0';
                      $listNamePos1 = '0';
                      $listNamePos2 = '0';
                    }
                  }
                  my @valIn = split(',', $listName3);
                  foreach my $valIn1 (@valIn) {
                   if ($idxInput == int( $ref->{value}->{u32} )) {
                     $helper = $valIn1;
                   }
                    $idxInput++;
                  }
                  $idxInput = '0';
##########################################################################################################################################  
#Log 1, $ref->{value}->{u32};
#Log 1, $helper;
#                  if ( $hash->{Model} eq "sird" )
#                  {
#                    if ( int( $ref->{value}->{u32} ) == 0 )
#                    {
#                      $helper = "InternetRadio";
#                    }
#                  }
##########################################################################################################################################
                  $helper = encode_utf8($helper);
                  
                  return ($ref, $response2, $listName2, $listName3, $helper);
                }
                else
                {
                  Log 1, "SIRD Command Input wrong Parameter: " . $params;
                }
                return undef;
              }
            }   
	        }
#        }
  }
}


###############################
sub SIRD_PlayMode($$);
sub SIRD_PlayMode($$)
{
  my ( $name, $params ) = @_;
  my $response = "";
  my $responseHelper = "false";
  my $ref;
  my $helper = ' ';

  if (    $params eq "stop"
       || $params eq "play"
       || $params eq "pause"
       || $params eq "next"
       || $params eq "previous" )
  {
    if ( $params eq "stop" )
    {
      $helper = '0';
    }
    elsif ( $params eq "play" )
    {
      $helper = '1';
    }
    elsif ( $params eq "pause" )
    {
      $helper = '2';
    }
    elsif ( $params eq "next" )
    {
      $helper = '3';
    }
    elsif ( $params eq "previous" )
    {
      $helper = '4';
    }
    eval { SIRD_Com( $name, "netRemote.play.control", 2, $helper, 0 ); };
    if ($@)
    {
      ### catch block
      Log 1, "SIRD PlayMode error: $@";
      return undef;
    }
  }
  elsif ( $params eq '-1' )
  {
    $response = SIRD_Com( $name, "netRemote.play.status", 1, 0, 0 );
    $responseHelper = "true" if ! $response || ( $response =~ /fsapiResponse/ );
      my $refXML = eval {
        XMLin( $response, KeyAttr => {}, ForceArray => [] );
      };
      if($@) {
        $responseHelper = "false";
#Log 1, "PlayMode: XML-Error: ".$@;
      }
    if ( $responseHelper eq "true" )
    {
      $responseHelper = "false";
      $ref = XMLin( $response, KeyAttr => {}, ForceArray => [] );
      ## Überprüfen ob Abfrage in Ordnung war
      if ( $ref->{status} eq 'FS_OK' )
      {
        if ( int( $ref->{value}->{u8} ) == 0 )
        {
          return "idle";
        }
        elsif ( int( $ref->{value}->{u8} ) == 1 )
        {
          return "buffering";
        }
        elsif ( int( $ref->{value}->{u8} ) == 2 )
        {
          return "playing";
        }
        elsif ( int( $ref->{value}->{u8} ) == 3 )
        {
          return "paused";
        }
        elsif ( int( $ref->{value}->{u8} ) == 4 )
        {
          return "rebuffering";
        }
        elsif ( int( $ref->{value}->{u8} ) == 5 )
        {
          return "error";
        }
        else
        {
          return "unknown";
        }
      }
    }
  }
  else
  {
    Log 1, "SIRD Command PlayStatus wrong Parameter: " . $params;
  }
  return undef;
}
###############################
sub SIRD_NavStatus($$);
sub SIRD_NavStatus($$)
{
  my ( $name, $params ) = @_;
  my $response = "";
  my $responseHelper = "false";
  my $ref;
  my $helper = ' ';
  ##########################################
  # read only
  # notifying
  ##########################################
  if ( $params eq '-1' )
  {
    $response = SIRD_Com( $name, "netRemote.nav.status", 1, $0, 0 );
    $responseHelper = "true" if ! $response || ( $response =~ /fsapiResponse/ );
      my $refXML = eval {
        XMLin( $response, KeyAttr => {}, ForceArray => [] );
      };
      if($@) {
        $responseHelper = "false";
#Log 1, "NavStatus: XML-Error: ".$@;
      }
    if ( $responseHelper eq "true" )
    {
      $responseHelper = "false";
      $ref = XMLin( $response, KeyAttr => {}, ForceArray => [] );
      ## Überprüfen ob Abfrage in Ordnung war
      if ( $ref->{status} eq 'FS_OK' )
      {
        if ( int( $ref->{value}->{u8} ) == 0 )
        {
          return "waiting";
        }
        elsif ( int( $ref->{value}->{u8} ) == 1 )
        {
          return "ready";
        }
        elsif ( int( $ref->{value}->{u8} ) == 2 )
        {
          return "fail";
        }
        elsif ( int( $ref->{value}->{u8} ) == 3 )
        {
          return "fatalError";
        }
        elsif ( int( $ref->{value}->{u8} ) == 4 )
        {
          return "readyRoot";
        }
        else
        {
          return "unknown";
        }
      }
    }
  }
  else
  {
    Log 1, "SIRD Command NavStatus wrong Parameter: " . $params;
  }
  return undef;
}
###############################
sub SIRD_NavCaps($$);
sub SIRD_NavCaps($$)
{
  my ( $name, $params ) = @_;
  my $response = "";
  my $responseHelper = "false";
  my $ref;
  my $helper = ' ';
  ##########################################
  # read only
  ##########################################
  if ( $params eq '-1' )
  {
    $response = SIRD_Com( $name, "netRemote.nav.caps", 1, $0, 0 );
    $responseHelper = "true" if ! $response || ( $response =~ /fsapiResponse/ );
      my $refXML = eval {
        XMLin( $response, KeyAttr => {}, ForceArray => [] );
      };
      if($@) {
        $responseHelper = "false";
#Log 1, "NavCaps: XML-Error: ".$@;
      }
    if ( $responseHelper eq "true" )
    {
      $responseHelper = "false";
      $ref = XMLin( $response, KeyAttr => {}, ForceArray => [] );
      ## Überprüfen ob Abfrage in Ordnung war
      if ( $ref->{status} eq 'FS_OK' )
      {
        return sprintf "%s", int( $ref->{value}->{u32} );
      }
    }
  }
  else
  {
    Log 1, "SIRD Command NavCaps wrong Parameter: " . $params;
  }
  return undef;
}
###############################
sub SIRD_NavNumItems($$);
sub SIRD_NavNumItems($$)
{
  my ( $name, $params ) = @_;
  my $response = "";
  my $responseHelper = "false";
  my $ref;
  my $helper = ' ';
  ##########################################
  # read only
  ##########################################
  if ( $params eq '-1' )
  {
    $response = SIRD_Com( $name, "netRemote.nav.numItems", 1, $0, 0 );
    $responseHelper = "true" if ! $response || ( $response =~ /fsapiResponse/ );
      my $refXML = eval {
        XMLin( $response, KeyAttr => {}, ForceArray => [] );
      };
      if($@) {
        $responseHelper = "false";
      }
    if ( $responseHelper eq "true" )
    {
      $responseHelper = "false";
      $ref = XMLin( $response, KeyAttr => {}, ForceArray => [] );
      ## Überprüfen ob Abfrage in Ordnung war
      if ( $ref->{status} eq 'FS_OK' )
      {
        return sprintf "%s", int( $ref->{value}->{s32} );
      }
    }
  }
  else
  {
    Log 1, "SIRD Command NavNumItems wrong Parameter: " . $params;
  }
  return undef;
}
###############################
sub SIRD_NavList($$$);
sub SIRD_NavList($$$)
{
  my ( $name, $start, $end ) = @_;
  my $helper = "unknown";
  my $response = SIRD_Com( $name, "netRemote.nav.list", 3, $start, $end );
  my $responseHelper = "false";
  my $ref;

#Log 1, "Response: ".$response;              
  $responseHelper = "true" if ! $response || ( $response =~ /fsapiResponse/ );
    my $refXML = eval {
      XMLin( $response, KeyAttr => {}, ForceArray => [] );
    };
    if($@) {
      $responseHelper = "false";
    }
  if ( $responseHelper eq "true" )
  {
    $responseHelper = "false";
    $ref = XMLin( $response, KeyAttr => {}, ForceArray => [] );
    ## Überprüfen ob Abfrage in Ordnung war
    if ( $ref->{status} eq 'FS_OK' )
    {
      return $ref;
    }
  }
  return undef;
}
###############################
sub SIRD_PresetList($$);
sub SIRD_PresetList($$)
{
  my ( $name, $params ) = @_;
  my $response = "";
  my $responseHelper = "false";
  my $ref;
  my $helper = ' ';
  my $preset = "";
  my $presetList1  = "";
  my $presetList2  = "";
  my $presetListC  = '0';
  my $FC = '0';
  ##########################################
  # read only
  ##########################################
    if ( $params eq '-1' )
    {
      $response = SIRD_Com( $name, "netRemote.nav.presets", 3, -1, 20 );
      $responseHelper = "true" if ! $response || ( $response =~ /fsapiResponse/ );
      my $refXML = eval {
        XMLin( $response, KeyAttr => {}, ForceArray => [] );
      };
      if($@) {
        $responseHelper = "false";
      }
      if ( $responseHelper eq "true" )
      {
        $responseHelper = "false";
        $ref = XMLin( $response, KeyAttr => {}, ForceArray => [] );
        ## Überprüfen ob Abfrage in Ordnung war
        if ( $ref->{status} eq 'FS_OK' )
        {
          if ( defined( $ref ) && ref( $ref->{item} ) eq "ARRAY" )
          {
            if ( ref( $ref->{'item'} ) eq "ARRAY" )
            {
              for my $item ( @{ $ref->{'item'} } )
              {
                if ( exists $item->{'field'}->{c8_array} && ref( $item->{'field'}->{c8_array} ) ne "HASH" )
                {
                  # Im HASH: Leerzeichen entfernen und in utf umwandeln
                  $item->{'field'}->{c8_array} = SIRD_xml2txt( SIRD_space2sub( $item->{'field'}->{c8_array} ) );
                }
                $presetListC++;
                if ($presetListC >= 10) {
                  $presetListC = '0'
                }
                # $presetliste mit Kommas zusammenbauen
                my $listName = $item->{'field'}->{c8_array};
                while ($listName =~ /HASH/) {
                  $listName = "--PRESET-FREE--";
                }
                if ($presetListC >= 1 && $presetListC <= 5) {
                  $presetList1 .= "<P".$presetListC.": ";
                  $presetList1 .= $listName;
                  $presetList1 .= ">";
                }
                else {
                  $presetList2 .= "<P".$presetListC.": ";
                  $presetList2 .= $listName;
                  $presetList2 .= ">";
                }
                if ( $preset ne "" )
                {
                $preset .= ',';
                }
                $preset .= $listName;
              }
              return ($ref, encode_utf8($preset), encode_utf8($presetList1), encode_utf8($presetList2));
            }
          }
        }
      }
    }
    else
    {
      Log 1, "SIRD Command PresetList wrong Parameter: " . $params;
    }

    return undef;
}
###############################
sub SIRD_SearchTerm($$);
sub SIRD_SearchTerm($$)
{
  my ( $name, $params ) = @_;
  my $response = "";
  my $responseHelper = "false";
  my $ref;
  my $helper = ' ';

  if ( $params ne '-1' )
  {
    eval { SIRD_Com( $name, "netRemote.nav.searchTerm", 2, $params, 0 ); };
    if ($@)
    {
      ### catch block
      Log 1, "SIRD SearchTerm error: $@";
      return undef;
    }
    return SIRD_SearchTerm( $name, -1 );
  }
  else
  {
    $response = SIRD_Com( $name, "netRemote.nav.searchTerm", 1, 0, 0 );
    $responseHelper = "true" if ! $response || ( $response =~ /fsapiResponse/ );
      my $refXML = eval {
        XMLin( $response, KeyAttr => {}, ForceArray => [] );
      };
      if($@) {
        $responseHelper = "false";
#Log 1, "SearchTerm: XML-Error: ".$@;
      }
    if ( $responseHelper eq "true" )
    {
      $responseHelper = "false";
      $ref = XMLin( $response, KeyAttr => {}, ForceArray => [] );
      ## Überprüfen ob Abfrage in Ordnung war
      if ( $ref->{status} eq 'FS_OK' )
      {
        if ( !ref $ref->{value}->{c8_array} )
        {
          return encode_utf8( $ref->{value}->{c8_array} );
        }
      }
    }
  }
  return undef;
}
##############################
sub SIRD_DABScan($$);
sub SIRD_DABScan($$)
{

  #notifying
  my ( $name, $params ) = @_;
  my $response = "";
  my $responseHelper = "false";
  my $ref;
  my $helper = ' ';

  if ( $params eq "idle" || $params eq "scan" )
  {
    if ( $params eq "scan" )
    {
      $helper = '1';
    }
    elsif ( $params eq "idle" )
    {
      $helper = '0';
    }
    eval
    {
      SIRD_Com( $name, "netRemote.nav.action.dabScan", 2, $helper, 0 );
    };
    if ($@)
    {
      ### catch block
      Log 1, "SIRD DABScan error: $@";
      return 0;
    }
    return SIRD_DABScan( $name, -1 );
  }
  elsif ( $params eq '-1' )
  {
    $response = SIRD_Com( $name, "netRemote.nav.action.dabScan", 1, 0, 0 );
    $responseHelper = "true" if ! $response || ( $response =~ /fsapiResponse/ );
      my $refXML = eval {
        XMLin( $response, KeyAttr => {}, ForceArray => [] );
      };
      if($@) {
        $responseHelper = "false";
#Log 1, "DABScan: XML-Error: ".$@;
      }
    if ( $responseHelper eq "true" )
    {
      $responseHelper = "false";
      $ref = XMLin( $response, KeyAttr => {}, ForceArray => [] );
      ## Überprüfen ob Abfrage in Ordnung war
      if ( $ref->{status} eq 'FS_OK' )
      {
        if ( $ref->{value}->{u8} == 0 )
        {
          return "idle";
        }
        else
        {
          return "scan";
        }
      }
    }
  }
  else
  {
    Log 1, "SIRD Command DABScan wrong Parameter: " . $params;
  }
  return undef;
}
###############################
sub SIRD_Logoff($);
sub SIRD_Logoff($)
{
  my ($hash) = @_;

  return 1;
}


###############################
sub SIRD_xml2txt($);
sub SIRD_xml2txt($)
{

  # stolen from   71_YAMAHA_AVR.pm
  # sub YAMAHA_AVR_html2txt($)
  my ($string) = @_;

  #$string =~ s/&nbsp;/ /g;
  #$string =~ s/&amp;/&/g;
  #$string =~ s/(\xe4|&auml;)/ä/g;
  #$string =~ s/(\xc4|&Auml;)/Ä/g;
  #$string =~ s/(\xf6|&ouml;)/ö/g;
  #$string =~ s/(\xd6|&Ouml;)/Ö/g;
  #$string =~ s/(\xfc|&uuml;)/ü/g;
  #$string =~ s/(\xdc|&Uuml;)/Ü/g;
  #$string =~ s/(\xdf|&szlig;)/ß/g;
  #$string =~ s/<.+?>//g;
  #$string =~ s/(^\s+|\s+$)//g;
  #$string =~ s/(\s+$)//g;
  return $string;
}

###############################
sub SIRD_space2sub ($)
{

  # Space in Untersrich wandeln
  my ($string) = @_;
  $string =~ s/ //g;
  $string =~ s/,/./g;
  $string =~ s/(\s+$)//g;
  return $string;
}

###############################
sub SIRD_refresh($);                                                                     
sub SIRD_refresh($)
{
  my ($name) = @_;

#      FW_directNotify("#FHEMWEB:$name", "location.reload(true);","" );
  FW_directNotify("#FHEMWEB:$name", "location.reload();","" );
}


1;

=pod
=item summary    command radios based on Frontier Silicon chips via FSAPI
=item summary_DE Steuerung von Radios auf Basisn von Frontier Silicon Chips via FSAPI

=begin html

<a name="SIRD"></a>
<h3>SIRD</h3>
<ul>
Please see german documentation at <a href="commandref_DE.html#SIRD">SIRD</a>
</ul>

=end html

=begin html_DE

<a name="SIRD"></a>
<h3>SIRD</h3>
<ul>
  <a name="SIRDdefine"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; SIRD &lt;radio_ip_address&gt; &lt;password&gt; &lt;model&gt; [&lt;interval&gt;]</code>
    <br><br>
    Dieses Modul steuert Radios auf Basis von Frontier Silicon Chips, die über FSAPI angesprochen werden können.<br>
    Für weitere Hinweise, Beschreibungen und Updates bitte auch im Forum unter https://forum.fhem.de/index.php/topic,32030.0.html nachschauen.<br><br>
    Benötigt die Module:<br>
    <ul>
    <li><code>HttpUtils</code></li>
    <li><code>Encode</code></li>
    <li><code>XML::Simple</code></li>
    </ul>
    <br><br>
   <b>Parameter:</b><br>
   <ul>
      <li><code>&lt;radio_ip_address&gt;</code>: Die IP-Adresse des Radios.</li>
   </ul>
      <ul>
      <li><code>&lt;password&gt;</code>: Das Passwort des Internetradios, normalerweise 1234.</li>
   </ul>
   <ul>
      <li><code>&lt;mode&gt;</code>: Verschiedene Modi
      <ul>
        <li><code>sird14</code>: SILVERCREST® (Verkauf durch LIDL®) Stereo-Internetradio SIRD 14 B1 / C2 und kompatible (Alter Modus wird bald entfernt. Bitte Neuen verwenden !!!)</li>
        <li><code>sird14b1</code>: SILVERCREST® (Verkauf durch LIDL®) Stereo-Internetradio SIRD 14 B1 und kompatible</li>
        <li><code>sird14c2</code>: SILVERCREST® (Verkauf durch LIDL®) Stereo-Internetradio SIRD 14 C2 und kompatible</li>
        <li><code>IR110</code>: Hama® Stereo-Internetradio IR110 und kompatible</li>
        <li><code>MD87238</code>: Medion® (Verkauf durch ALDI®) Stereo-Internetradio MD 87238 und kompatible</li>
      </ul>
      </li>
   </ul>
   <br>
   <b>Optional</b><br>
   <ul>
      <li><code>&lt;[interval]&gt;</code>: Interval, in dem der Status des Radios abgefragt wird in Sekunden. Standard: 300 Sekunden</li> 
   </ul><br><br>
  </ul>
  <a name="SIRDset"></a>
  <b>Set</b>
  <ul>
    <li><code>channelDown</code></li>
    <li><code>channelUp</code></li>
    <li><code>channelUp</code></li>
    <li><code>clearreadings</code></li>
    <li><code>input</code></li>
    <li><code>mute</code></li>
    <li><code>navActionNavi</code></li>
    <li><code>navActionSelItem</code></li>
    <li><code>navCapsRequest</code></li>
    <li><code>navList</code></li>
    <li><code>navListRequest</code></li>
    <li><code>off</code></li>
    <li><code>on</code></li>
    <li><code>pause</code></li>
    <li><code>play</code></li>
    <li><code>preset</code></li>
    <li><code>presetListRequest</code></li>
    <li><code>remoteState</code></li>
    <li><code>repeat</code></li>
    <li><code>searchTerm</code></li>
    <li><code>shuffle</code></li>
    <li><code>statusRequest</code></li>
    <li><code>stop</code></li>
    <li><code>volume</code></li>
    <li><code>volumeDown</code></li>
    <li><code>volumeStraight</code></li>
    <li><code>volumeUp</code></li>
  </ul>
  <a name="SIRDget"></a>
  <b>Get</b>
  <ul>
    <li><code>currentAlbum</code></li>
    <li><code>currentArtist</code></li>
    <li><code>currentTitel</code></li>
    <li><code>input</code></li>
    <li><code>lastcommand</code></li>
    <li><code>mute</code></li>
    <li><code>playStatus</code></li>
    <li><code>power</code></li>
    <li><code>presence</code></li>
    <li><code>repeat</code></li>
    <li><code>shuffle</code></li>
    <li><code>state</code></li>
    <li><code>volume</code></li>
    <li><code>volumeStraight</code></li>
  </ul>
</ul>
=end html_DE
