#oodist: *** DO NOT USE THIS VERSION FOR PRODUCTION ***
#oodist: This file contains OODoc-style documentation which will get stripped
#oodist: during its release in the distribution.  You can use this file for
#oodist: testing, however the code of this development version may be broken!

package Mail::Transport::Exim;
use parent 'Mail::Transport::Send';

use strict;
use warnings;

use Log::Report   'mail-transport', import => [ qw/__x error fault warning/ ];

use Scalar::Util  qw/blessed/;

#--------------------
=chapter NAME

Mail::Transport::Exim - transmit messages using external Exim program

=chapter SYNOPSIS

  my $sender = Mail::Transport::Exim->new(...);
  $sender->send($message);

=chapter DESCRIPTION

Implements mail transport using the external C<'Exim'> program.
When instantiated, the mailer will look for the binary in specific system
directories, and the first version found is taken.

=chapter METHODS

=c_method new %options
If you have Exim installed in a non-standard location, you will need to
specify the path, using M<new(proxy)>.

=default via C<'exim'>
=error cannot find binary for exim.
=cut

sub init($)
{	my ($self, $args) = @_;
	$args->{via} = 'exim';
	$self->SUPER::init($args);

	$self->{MTS_program} = $args->{proxy} ||
		( -x '/usr/sbin/exim4' ? '/usr/sbin/exim4' : undef) || $self->findBinary('exim', '/usr/exim/bin')
		or error __x"cannot find binary for exim.";

	$self;
}

=method trySend $message, %options
=error Errors when closing Exim mailer $program: $!
The Exim mail transfer agent did start, but was not able to handle the message
correctly.

=fault cannot open pipe to $program: $!
=fault errors when closing Exim mailer $program: $!
=cut

sub trySend($@)
{	my ($self, $message, %args) = @_;

	my $from = $args{from} || $message->sender;
	$from    = $from->address if blessed $from && $from->isa('Mail::Address');
	my @to   = map $_->address, $self->destinations($message, $args{to});

	my $program = $self->{MTS_program};
	my $mailer;
	if(open($mailer, '|-')==0)
	{	{ exec $program, '-i', '-f', $from, @to; }  # {} to avoid warning
		fault __x"cannot open pipe to {program}", program => $program;
	}

	$self->putContent($message, $mailer, undisclosed => 1);

	$mailer->close
		or fault __x"errors when closing Exim mailer {program}", program => $program;

	1;
}

1;
