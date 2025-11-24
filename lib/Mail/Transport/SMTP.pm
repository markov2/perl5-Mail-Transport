#oodist: *** DO NOT USE THIS VERSION FOR PRODUCTION ***
#oodist: This file contains OODoc-style documentation which will get stripped
#oodist: during its release in the distribution.  You can use this file for
#oodist: testing, however the code of this development version may be broken!

package Mail::Transport::SMTP;
use parent 'Mail::Transport::Send';

use strict;
use warnings;

use Log::Report   'mail-transport';

use Net::SMTP     ();

use constant CMD_OK      => 2;

#--------------------
=chapter NAME

Mail::Transport::SMTP - transmit messages without external program

=chapter SYNOPSIS

  my $sender = Mail::Transport::SMTP->new(...);
  $sender->send($message);

  $message->send(via => 'smtp');

=chapter DESCRIPTION

This module implements transport of C<Mail::Message> objects by negotiating
to the destination host directly by using the SMTP protocol, without help of
C<sendmail>, C<mail>, or other programs on the local host.

B<warning:> you may need to install Net::SMTPS, to get TLS support.

=chapter METHODS

=c_method new %options

=default hostname <from Net::Config>
=default proxy    <from Net::Config>
=default via      C<'smtp'>
=default port     C<25>

=option  smtp_debug BOOLEAN
=default smtp_debug false
Simulate transmission: the SMTP protocol output will be sent to your screen.

=option  helo $host
=default helo <from Net::Config>
The fully qualified name of the sender's $host (your system) which
is used for the greeting message to the receiver.  If not specified,
Net::Config or else Net::Domain are questioned to find it.
When even these do not supply a valid name, the name of the domain in the
C<From> line of the message is assumed.

=option  timeout $wait
=default timeout 120
The number of seconds to $wait for a valid response from the server before
failing.

=option  username $username
=default username undef
Use SASL authentication to contact the remote SMTP server (RFC2554).
This $username in combination with P<password> is passed as arguments
to Net::SMTP method auth.  Other forms of authentication are not
supported by Net::SMTP.  The P<username> can also be specified as an
Authen::SASL object.

=option  password $password
=default password undef
The password to be used with the P<username> to log in to the remote
server.

=option  esmtp_options \%opts
=default esmtp_options {}
[2.116] ESMTP options to pass to Net::SMTP.  See the L<Net::SMTP>
documentation for full details. Options can also be passed at send time.
For example: C<< { XVERP => 1 } >>

=option  from $address
=default from undef
Allows a default sender $address to be specified globally.
See M<trySend()> for full details.

=cut

sub init($)
{	my ($self, $args) = @_;
	$args->{via}  ||= 'smtp';
	$args->{port} ||= '25';

	my $hosts   = $args->{hostname};
	unless($hosts)
	{	require Net::Config;
		$hosts  = $Net::Config::NetConfig{smtp_hosts};
		undef $hosts unless @$hosts;
		$args->{hostname} = $hosts;
	}

	$self->SUPER::init($args) or return;

	my $helo = $args->{helo}
		|| eval { require Net::Config; $Net::Config::NetConfig{inet_domain} }
		|| eval { require Net::Domain; Net::Domain::hostfqdn() };

	$self->{MTS_net_smtp_opts} = +{ Hello => $helo, Debug => ($args->{smtp_debug} || 0) };
	$self->{MTS_esmtp_options} = $args->{esmtp_options};
	$self->{MTS_from}          = $args->{from};
	$self;
}

=method trySend $message, %options
Try to send the $message once.   This may fail, in which case this
method will return false.  In list context, the reason for failure
can be caught: in list context C<trySend> will return a list of
six values:

  (success, rc, rc-text, error location, quit success, accept)

Success and quit success are booleans.  The error code and -text are
protocol specific codes and texts.  The location tells where the
problem occurred.

[3.003] the 'accept' returns the message of the L<dataend()> instruction.
Some servers may provide useful information in there, like an internal
message registration id.  For example, postfix may return "2.0.0 Ok:
queued as 303EA380EE".  You can only use this parameter when running
local delivery (which is a smart choice anyway)

=option  to $address|\@addresses
=default to []
Alternative destinations.  If not specified, the C<To>, C<Cc> and C<Bcc>
fields of the header are used.  An $address is a string or a Mail::Address
object.

=option  from $address
=default from E<lt> E<gt>
Your own identification.  This may be fake.  If not specified, it is
taken from M<Mail::Message::sender()>, which means the content of the
C<Sender> field of the message or the first address of the C<From>
field.  This defaults to "E<lt> E<gt>", which represents "no address".

=option  esmtp_options \%opts
=default esmtp_options {}
Additional or overridden EMSTP options. See M<new(esmtp_options)>

=notice No addresses found to send the message to, no connection made

=cut

sub trySend($@)
{	my ($self, $message, %args) = @_;
	my %send_options = ( %{$self->{MTS_esmtp_options} || {}}, %{$args{esmtp_options} || {}} );

	# From whom is this message.
	my $from = $args{from} || $self->{MTS_from} || $message->sender || '<>';
	$from = $from->address if ref $from && $from->isa('Mail::Address');

	# Which are the destinations.
	! defined $args{To}
		or $self->log(WARNING => "Use option `to' to overrule the destination: `To' refers to a field");

	my @to = map $_->address, $self->destinations($message, $args{to});
	@to or $self->log(NOTICE => 'No addresses found to send the message to, no connection made'), return 1;

	#### Prepare the message.

	my $out = '';
	open my $fh, '>:raw', \$out;
	$self->putContent($message, $fh, undisclosed => 0);
	$out =~ m![\r\n]\z! or $out .= "\r\n";
	close $fh;

	#### Send

	my $server;
	if(wantarray)
	{	# In LIST context
		$server = $self->contactAnyServer
			or return (0, 500, "Connection Failed", "CONNECT", 0);

		$server->mail($from, %send_options)
			or return (0, $server->code, $server->message, 'FROM', $server->quit);

		foreach (@to)
		{	 next if $server->to($_);
			#???  must we be able to disable this?  f.i:
			#???     next if $args{ignore_erroneous_destinations}
			return (0, $server->code, $server->message, "To $_", $server->quit);
		}

		my $bodydata = $message->body->file;

		$server->datafast(\$out)  #!! destroys $out
			or return (0, $server->code, $server->message, 'DATA', $server->quit);

		my $accept = ($server->message)[-1];
		chomp $accept;

		my $rc     = $server->quit;
		return ($rc, $server->code, $server->message, 'QUIT', $rc, $accept);
	}

	# in SCALAR context
	$server = $self->contactAnyServer
		or return 0;

	$server->mail($from, %send_options)
		or ($server->quit, return 0);

	foreach (@to)
	{	next if $server->to($_);
		$server->quit;
		return 0;
	}

	$server->datafast(\$out)  #!! destroys $out
		or ($server->quit, return 0);

	$server->quit;
}

# Improvement on Net::CMD::datasend(), mainly bulk adding dots and avoiding copying
# About 79% performance gain on huge messages.
# Be warned: this method destructs the content of $data!
sub Net::SMTP::datafast($)
{	my ($self, $data) = @_;
	$self->_DATA or return 0;

	$$data =~ tr/\r\n/\015\012/ if "\r" ne "\015";  # mac
	$$data =~ s/(?<!\015)\012/\015\012/g;  # \n -> crlf as sep.  Needed?
	$$data =~ s/^\./../;                   # data starts with a dot, escape it
	$$data =~ s/\012\./\012../g;           # other lines which start with a dot

	$self->_syswrite_with_timeout($$data . ".\015\012");
	$self->response == CMD_OK;
}

#--------------------
=section Server connection

=method contactAnyServer
Creates the connection to the SMTP server.  When more than one hostname
was specified, the first which accepts a connection is taken.  An
IO::Socket::INET object is returned.
=cut

sub contactAnyServer()
{	my $self = shift;

	my ($enterval, $count, $timeout) = $self->retry;
	my ($host, $port, $username, $password) = $self->remoteHost;
	my @hosts = ref $host ? @$host : $host;
	my $opts  = $self->{MTS_net_smtp_opts};

	foreach my $host (@hosts)
	{	my $server = $self->tryConnectTo($host, Port => $port, %$opts, Timeout => $timeout)
			or next;

		$self->log(PROGRESS => "Opened SMTP connection to $host.");

		if(defined $username)
		{	unless($server->auth($username, $password))
			{	$self->log(ERROR => "Authentication failed.");
				return undef;
			}
			$self->log(PROGRESS => "$host: Authentication succeeded.");
		}

		return $server;
	}

	undef;
}

=method tryConnectTo $host, %options
Try to establish a connection to deliver SMTP to the specified $host.  The
%options are passed to the C<new> method of Net::SMTP.
=cut

sub tryConnectTo($@)
{	my ($self, $host) = (shift, shift);
	Net::SMTP->new($host, @_);
}

1;
