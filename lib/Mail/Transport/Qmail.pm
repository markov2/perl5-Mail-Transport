# This code is part of distribution Mail-Transport.  Meta-POD processed with
# OODoc into POD and HTML manual-pages.  See README.md
# Copyright Mark Overmeer.  Licensed under the same terms as Perl itself.

package Mail::Transport::Qmail;
use base 'Mail::Transport::Send';

use strict;
use warnings;

use Carp;

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
{   my ($self, $args) = @_;
    $args->{via} = 'qmail';

    $self->SUPER::init($args) or return;

    $self->{MTM_program} = $args->{proxy} || $self->findBinary('qmail-inject', '/var/qmail/bin') || return;
    $self;
}

=method trySend $message, %options

=error Errors when closing Qmail mailer $program: $!
The Qmail mail transfer agent did start, but was not able to handle the
message for some specific reason.

=cut

sub trySend($@)
{   my ($self, $message, %args) = @_;

    my $program = $self->{MTM_program};
    my $mailer;
    if(open($mailer, '|-')==0)
    {   { exec $program; }
        $self->log(NOTICE => "Errors when opening pipe to $program: $!");
        exit 1;
    }
 
    $self->putContent($message, $mailer, undisclosed => 1);

    unless($mailer->close)
    {   $self->log(ERROR => "Errors when closing Qmail mailer $program: $!");
        $? ||= $!;
        return 0;
    }

    1;
}

1;
