#!/usr/bin/perl -w

our $VERSION='0.20220527';

=head1 NAME

ipc_open3_example.pl - shows how to use IPC::Open3 by streaming a compressed file into the gzip command.

=head1 SYNOPSIS

	perl ipc_open3_example.pl

=head1 DESCRIPTION

	Reads LoremIpsum.gz, sends it through "gzip -d" and prints results onscreen

=head1 HOW TO READ OTHER STREAMS

	/usr/bin/compress -d|
	/usr/bin/gzip -d
	/usr/bin/bzip2 -d
	/usr/bin/xz -d|
	/usr/local/bin/brotli -d -f

=cut

######################################################################

use strict;
use warnings FATAL => 'all';
use IPC::Open3;


my($can_read,$can_write,$has_err)=(1,2,4);

$SIG{CHLD} = 'IGNORE'; # Tell exiting-children that we don't care about their exist codes (usually captured below from their STDERR anyhow), allowing their processes to end. # https://docstore.mik.ua/orelly/perl/cookbook/ch16_20.htm


my @cmd=('/usr/bin/gzip','-d');
pipe(my $to_zip,my $zip_err); # Create 2 file handles (because open3 cannot auto-vivify error handles)
my $pid = open3($to_zip, my $from_zip, $zip_err, @cmd); die "open3 failed: $@\n" if $@;
open(my $in_stream,'<','LoremIpsum.gz') or die $!; # Put a huge (e.g. 2gb) .bz2-compressed file here
my @buffsz; 
my $inzsz=0; 	# Can set this to larger number if you want your OS to buffer it - might cause blocking though ?
my $dbg=0;
foreach($in_stream, $zip_err, $from_zip, $to_zip){
  binmode($_) ;
  $buffsz[fileno($_)]=$inzsz ? $inzsz : (stat($_))[11] || 16384;	# Use the buffer size that the socket says it has
  print fileno($_) . " sz=" . $buffsz[fileno($_)] . "\n" if($dbg);
}


do {
  my $fhs=0;
  if($zip_err  && ($fhs=&handlestate($zip_err))  & ($can_read|$has_err))  { &check_zip_err($zip_err,$fhs); }
  if($from_zip && ($fhs=&handlestate($from_zip)) & ($can_read|$has_err))  { my($got,$buf)=&read_from_zip($from_zip,$fhs); print $buf if($got) }	# Unsets $from_zip at EOF
  if($to_zip   && ($fhs=&handlestate($to_zip))   & ($can_write|$has_err)) {
    if($fhs & $has_err) {
      print "zip write is in error state\n";
    } else { # Zip is Writable
      if($in_stream && ($fhs=&handlestate($in_stream))  & ($can_read|$has_err))  {
        if($fhs & $has_err) {
          print "zip write is in error state\n";
        } else { # grab input and send to zip
	  my($got,$dat)=&get_from_stream($in_stream,$fhs);	# get_from_stream closes in_stream at EOF
          if(!$got) {close($to_zip); undef $to_zip;}		# Tell child that no more input is coming to it
	  my $leftover=&send_to_zip($to_zip, $got, $dat) if($got);
	  die "leftover=$leftover\n" if($got && length($leftover)); # Can syswrite ever send only part of the buffer? Probably no.
	}
      }
    }
  }
} while($from_zip);



sub handlestate {	# Return a bitstring representing the state of the supplied handle: $can_read | $can_write | $has_err
  my($fh)=@_;
  my $vec='';vec($vec,fileno($fh),1)=1;
  my($nfound, $timeleft)=select(my $rin=$vec,my $win=$vec,my $ein=$vec,0);
  print "fn: ".fileno($fh)." nfound=$nfound timeleft=$timeleft rin=" . unpack("b*",$rin) . " win=" . unpack("b*",$win) . " ein=" . unpack("b*",$ein) . "\n" if($dbg);
  return ($rin eq $vec ? $can_read : 0) + ($win eq $vec ? $can_write : 0) + ($ein eq $vec ? $has_err: 0);
} # handlestate


sub check_zip_err {	# Called when STDERR from the subprocess child has something it wants to tell us
  my($fh,$fhs)=@_;
  if($fhs & $has_err) { warn "Ziperr $fhs=$has_err in error state";}	# The STDERR handle itself has some error of its own
  if($fhs & $can_read) {
    my $got=sysread($fh,my $buf,$buffsz[fileno($fh)]);	# Get childs STDOUT
    if(!$got) { # EOF
      close($fh); undef $_[0];
    } else {
      warn "err: got=$got err=$buf";	# This triggers on exit, like stdout does, with 0 bytes indicating the end
    }
    return($got,$buf);	# 0 means EOF
  }
  return undef;
} # check_zip_err


sub get_from_stream {	# Read the binary intput file which is going to be fed to the child unzipping stream. Called as long as $in_stream is readable
  my($fh,$fhs)=@_;
  if($fhs & $has_err) { warn "Input stream ".(fileno($fh))." in error state";}
  if($fhs & $can_read) {
    my $got=sysread($fh,my $buf,$buffsz[fileno($fh)]);
    if(!$got) { # EOF
      close($fh); undef $_[0];
    }
    #print "in $buf]n";
    return($got,$buf);	# 0 means EOF
  }
  return undef;
} # get_from_stream


sub send_to_zip {	# Sent the specified data (if any) to the unzipper's input handle.  Only called when the unzipper input is writable
  my($fh,$got,$dat)=@_;
  # should not write more than $buffsz[fileno($fh)] at a time though...
  my $sent=syswrite($fh,$dat) if($got);	# $buffsz[fileno($fh)]
  die "short write" if($sent && $sent != length($dat));
  return substr($dat,$sent); # return any leftover
} # send_to_zip


sub read_from_zip {	# Get the decompressed output.  Only called when readable
  my($fh,$fhs)=@_;
  if($fhs & $has_err) { warn "Zip input stream ".(fileno($fh))." in error state";}
  if($fhs & $can_read) {
    my $got=sysread($fh,my $buf,$buffsz[fileno($fh)]);
    print "zip_in got $got b=$buf\n" if($dbg);
    if(!$got) { # EOF
      close($fh); undef $_[0];
    }
    return($got,$buf); # 0 means EOF
  }
  return undef;
} # read_from_zip

