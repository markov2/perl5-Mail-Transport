# This code is part of distribution Mail-Transport.  Meta-POD processed with
# OODoc into POD and HTML manual-pages.  See README.md
# Copyright Mark Overmeer.  Licensed under the same terms as Perl itself.

package Mail::Transport::Exim;
use base 'Mail::Transport::Send';

use strict;
use warnings;

use Carp;

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
=cut

sub init($)
{   my ($self, $args) = @_;
    $args->{via} = 'exim';

    $self->SUPER::init($args) or return;

    $self->{MTS_program} = $args->{proxy}
     || ( -x '/usr/sbin/exim4' ? '/usr/sbin/exim4' : undef)
     || $self->findBinary('exim', '/usr/exim/bin')
     || return;

    $self;
}

=method trySend $message, %options
=error Errors when closing Exim mailer $program: $!
The Exim mail transfer agent did start, but was not able to handle the message
correctly.
=cut

sub trySend($@)
{   my ($self, $message, %args) = @_;

    my $from = $args{from} || $message->sender;
    $from    = $from->address if ref $from && $from->isa('Mail::Address');
    my @to   = map $_->address, $self->destinations($message, $args{to});

    my $program = $self->{MTS_program};
    my $mailer;
    if(open($mailer, '|-')==0)
    {   { exec $program, '-i', '-f', $from, @to; }  # {} to avoid warning
        $self->log(NOTICE => "Errors when opening pipe to $program: $!");
        exit 1;
    }

    $self->putContent($message, $mailer, undisclosed => 1);

    unless($mailer->close)
    {   $self->log(ERROR => "Errors when closing Exim mailer $program: $!");
        $? ||= $!;
        return 0;
    }

    1;
}

1;
