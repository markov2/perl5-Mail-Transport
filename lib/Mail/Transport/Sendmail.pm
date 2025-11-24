#oodist: *** DO NOT USE THIS VERSION FOR PRODUCTION ***
#oodist: This file contains OODoc-style documentation which will get stripped
#oodist: during its release in the distribution.  You can use this file for
#oodist: testing, however the code of this development version may be broken!

package Mail::Transport::Sendmail;
use parent 'Mail::Transport::Send';

use strict;
use warnings;

use Log::Report   'mail-transport';

#--------------------
=chapter NAME

Mail::Transport::Sendmail - transmit messages using external Sendmail program

=chapter SYNOPSIS

  my $sender = Mail::Transport::Sendmail->new(...);
  $sender->send($message);

=chapter DESCRIPTION

Implements mail transport using the external C<'Sendmail'> program.
When instantiated, the mailer will look for the binary in specific system
directories, and the first version found is taken.

Some people use Postfix as MTA.  Postfix can be installed as replacement
for Sendmail: is provides a program with the same name and options.  So,
this module supports postfix as well.

B<WARNING:> When you do bulk email sending with local delivery via
Postfix, you can probably better use the SMTP backend to connect
to postfix.  The C<sendmail> command delivers to C<maildrop>.  From
C<maildrop>, the C<pickupd> will only sequentially insert messages
into C<cleanup>.  That process can take considerable elapse time.
Directly inserting via C<smtpd> will parallellize the cleanup process.

=chapter METHODS

=c_method new %options

=default via C<'sendmail'>

=option  sendmail_options ARRAY
=default sendmail_options []
Add to the command-line of the started sendmail MTU a list of
separate words.  So say C< [ '-f', $file ] > and not C< [ "-f $file" ] >,
because the latter will be taken by sendmail as one word only.

=cut

sub init($)
{	my ($self, $args) = @_;
	$args->{via} = 'sendmail';
	$self->SUPER::init($args);

	$self->{MTS_program} = $args->{proxy} || $self->findBinary('sendmail') or return;
	$self->{MTS_opts} = $args->{sendmail_options} || [];
	$self;
}

#--------------------
=section Sending mail

=method trySend $message, %options

=option  sendmail_options ARRAY
=default sendmail_options undef

=fault cannot open pipe to $program: $!
=error Errors when closing sendmail mailer $program: $!
The was no problem starting the sendmail mail transfer agent, but for
some specific reason the message could not be handled correctly.

=cut

sub trySend($@)
{	my ($self, $message, %args) = @_;

	my $program = $self->{MTS_program};
	my $mailer;
	if(open($mailer, '|-')==0)
	{	# Child process is sendmail binary
		my $options = $args{sendmail_options} || [];
		my @to = map $_->address, $self->destinations($message, $args{to});

		# {} to avoid warning about code after exec
		{	exec $program, '-i', @{$self->{MTS_opts}}, @$options, @to; }
		fault __x"cannot open pipe to {program}", program => $program;
	}

	# Parent process is the main program, still
	$self->putContent($message, $mailer, undisclosed => 1);

	$mailer->close
		or fault __x"errors when closing sendmail mailer {program}", program => $program;

	1;
}

1;
