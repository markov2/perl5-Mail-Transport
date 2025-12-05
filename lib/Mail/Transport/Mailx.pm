#oodist: *** DO NOT USE THIS VERSION FOR PRODUCTION ***
#oodist: This file contains OODoc-style documentation which will get stripped
#oodist: during its release in the distribution.  You can use this file for
#oodist: testing, however the code of this development version may be broken!

package Mail::Transport::Mailx;
use parent 'Mail::Transport::Send';

use strict;
use warnings;

use Log::Report   'mail-transport', import => [ qw/__x fault error/ ];

#--------------------
=chapter NAME

Mail::Transport::Mailx - transmit messages using external mailx program

=chapter SYNOPSIS

  my $sender = Mail::Transport::Mailx->new(...);
  $sender->send($message);

=chapter DESCRIPTION

Implements mail transport using the external programs C<'mailx'>,
C<Mail>, or C<'mail'>.  When instantiated, the mailer will look for
any of these binaries in specific system directories, and the first
program found is taken.

B<WARNING: There are many security issues with mail and mailx. DO NOT USE
these commands to send messages which contains data derived from any
external source!!!>

Under Linux, freebsd, and bsdos the C<mail>, C<Mail>, and C<mailx> names are
just links to the same binary.  The implementation is very primitive, pre-MIME
standard,  what may cause many headers to be lost.  For these platforms (and
probably for other platforms as well), you can better not use this transport
mechanism.

=chapter METHODS

=c_method new %options

=default via   C<'mailx'>

=option  style 'BSD'|'RFC822'
=default style <autodetect>
There are two version of the C<mail> program.  The newest accepts
RFC822 messages, and automagically collect information about where
the message is to be send to.  The BSD style mail command predates
MIME, and expects lines which start with a C<'~'> (tilde) to specify
destinations and such.  This field is autodetect, however on some
platforms both versions of C<mail> can live (like various Linux
distributions).

=error cannot find binary of mailx.
=cut

sub init($)
{	my ($self, $args) = @_;
	$args->{via} = 'mailx';

	$self->SUPER::init($args) or return;

	$self->{MTM_program} = $args->{proxy} || $self->findBinary('mailx') || $self->findBinary('Mail') || $self->findBinary('mail')
		or error __x"cannot find binary of mailx.";

	$self->{MTM_style} = $args->{style} // ( $^O =~ m/linux|freebsd|bsdos|netbsd|openbsd/ ? 'BSD' : 'RFC822' );
	$self;
}

=method trySend $message, %options

=fault cannot open pipe to $program: $!
=fault sending via mailx mailer $program failed: $!
Mailx (in some shape: there are many different implementations) did start
accepting messages, but did not succeed sending it.
=cut

sub _try_send_bsdish($$)
{	my ($self, $message, $args) = @_;

	my @options = ('-s' => $message->subject);

	{	local $" = ',';
		my @cc  = map $_->format, $message->cc;
		push @options, ('-c' => "@cc")  if @cc;

		my @bcc = map $_->format, $message->bcc;
		push @options, ('-b' => "@bcc") if @bcc;
	}

	my @to      = map $_->format, $message->to;
	my $program = $self->{MTM_program};

	my $mailer;
	if((open $mailer, '|-')==0)
	{	close STDOUT;
		{	exec $program, @options, @to }
		fault __x"cannot open pipe to {program}", program => $program;
	}

	$self->putContent($message, $mailer, body_only => 1);

	$mailer->close
		or fault __x"errors when closing Mailx mailer {program}", program => $program;

	1;
}

sub trySend($@)
{	my ($self, $message, %args) = @_;

	return $self->_try_send_bsdish($message, \%args)
		if $self->{MTM_style} eq 'BSD';

	my $program = $self->{MTM_program};
	open my $mailer, '|-', $program, '-t'
		or fault __x"cannot open pipe to {program}", program => $program;

	$self->putContent($message, $mailer);

	$mailer->close
		or fault __x"errors when closing Mailx mailer {program}", program => $program;

	1;
}

1;
