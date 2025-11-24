#oodist: *** DO NOT USE THIS VERSION FOR PRODUCTION ***
#oodist: This file contains OODoc-style documentation which will get stripped
#oodist: during its release in the distribution.  You can use this file for
#oodist: testing, however the code of this development version may be broken!

package Mail::Transport::Qmail;
use parent 'Mail::Transport::Send';

use strict;
use warnings;

use Log::Report   'mail-transport';

#--------------------
=chapter NAME

Mail::Transport::Qmail - transmit messages using external Qmail program

=chapter SYNOPSIS

  my $sender = Mail::Transport::Qmail->new(...);
  $sender->send($message);

=chapter DESCRIPTION

Implements mail transport using the external programs C<'qmail-inject'>,
part of the qmail mail-delivery system.

=chapter METHODS

=c_method new %options
=default proxy C<'qmail-inject'>
=default via C<'qmail'>
=cut

sub init($)
{	my ($self, $args) = @_;
	$args->{via} = 'qmail';
	$self->SUPER::init($args);

	$self->{MTM_program} = $args->{proxy} || $self->findBinary('qmail-inject', '/var/qmail/bin') or return;
	$self;
}

=method trySend $message, %options
=error Errors when closing Qmail mailer $program: $!
The Qmail mail transfer agent did start, but was not able to handle the
message for some specific reason.

=fault cannot open pipe to $program: $!
=fault errors when closing Qmail mailer $program: $!
=cut

sub trySend($@)
{	my ($self, $message, %args) = @_;

	my $program = $self->{MTM_program};
	my $mailer;
	if(open($mailer, '|-')==0)
	{	{ exec $program; }
		fault __x"cannot open pipe to {program}.", program => $program;
	}

	$self->putContent($message, $mailer, undisclosed => 1);

	$mailer->close
        or fault __x"errors when closing Qmail mailer {program}", program => $program;

	1;
}

1;
