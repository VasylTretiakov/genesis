#!/usr/bin/perl
use strict;
use warnings;
use utf8;

use Expect;
use lib 't';
use helper;
use Cwd qw(abs_path);
use Test::Differences;
use Test::Output;
use Test::Deep;
use JSON::PP qw/decode_json/;

use lib 'lib';
use Genesis;
use Genesis::Top;

$ENV{NOCOLOR} = 1;

subtest 'secrets-v2.7.0' => sub {
	plan skip_all => 'skipping secrets tests because SKIP_SECRETS_TESTS was set'
		if $ENV{SKIP_SECRETS_TESTS};
	plan skip_all => 'secrets-v2.7.0 not selected test'
		if @ARGV && ! grep {$_ eq 'secrets-v2.7.0'} @ARGV;

	my $vault_target = vault_ok;
	bosh2_cli_ok;

	chdir workdir('genesis-2.7.0') or die;
	reprovision init => 'something', kit => 'secrets-2.7.0';

	my $env_name = 'c-azure-us1-dev';
	my $root_ca_path = '/secret/genesis-2.7.0/root_ca';
	my $secrets_mount = 'secret/genesis-2.7.0/deployments';
	my $secrets_path = 'dev/azure/us1';
	local $ENV{SAFE_TARGET} = $vault_target;
	runs_ok("safe x509 issue -A --name 'root_ca.genesisproject.io' $root_ca_path", "Can create a base root ca");

	my $cmd = Expect->new();
	$cmd->log_stdout($ENV{GENESIS_TRACE} ? 1 : 0);
	$cmd->spawn("genesis new $env_name --secrets-mount $secrets_mount --secrets-path /$secrets_path/ --root-ca-path $root_ca_path");

	expect_ok $cmd, [ "What is your base domain?", sub { $_[0]->send("demo.genesisproject.io\n"); }];
	expect_exit $cmd, 0, "genesis creates a new environment and auto-generates certificates - set secrets stuff to non-standard";

	my ($pass,$rc,$out) = runs_ok("genesis lookup $env_name .");
	my $properties;
	lives_ok {$properties = decode_json($out)} "genesis lookup on environment returns parsable json";

	# Feature: Setting the root_ca_path, secrets_mount and secrets_path on genesis new
	$secrets_mount = "/$secrets_mount/";
	is $properties->{genesis}{root_ca_path},  $root_ca_path,  "environment correctly specifies root ca path";
	is $properties->{genesis}{secrets_mount}, $secrets_mount, "environment correctly specifies secrets mount";
	is $properties->{genesis}{secrets_path},  $secrets_path,  "environment correctly specifies secrets path";

	# Feature: Secrets mount and path in use
	# Feature: Specify CA signer
	# Feature: Specify certificate key usage
	my $v = "$secrets_mount$secrets_path";
	($pass, $rc, $out) = runs_ok("genesis check-secrets $env_name", "genesis check-secrets runs without error");
	$out =~ s/(Duration:|-) \d+ seconds/$1 XXX seconds/g;
	matches_utf8 $out, <<EOF, "genesis new correctly created secrets of the correct type and location";
Parsing kit secrets descriptions ... done. - XXX seconds
Retrieving all existing secrets ... done. - XXX seconds

Checking 18 secrets for c-azure-us1-dev under path '/secret/genesis-2.7.0/deployments/dev/azure/us1/':
  [ 1/18] fixed/ca X509 certificate - CA, signed by '$root_ca_path' ... found.
  [ 2/18] fixed/server X509 certificate - signed by 'fixed/ca' ... found.
  [ 3/18] haproxy/ca X509 certificate - CA, signed by '/secret/genesis-2.7.0/root_ca' ... found.
  [ 4/18] haproxy/ssl X509 certificate - signed by 'haproxy/ca' ... found.
  [ 5/18] top-level/top X509 certificate - CA, signed by '$root_ca_path' ... found.
  [ 6/18] secondary/ca X509 certificate - CA, signed by 'top-level/top' ... found.
  [ 7/18] secondary/server X509 certificate - signed by 'secondary/ca' ... found.
  [ 8/18] top-level/server X509 certificate - signed by 'top-level/top' ... found.
  [ 9/18] openVPN/certs/root X509 certificate - CA, explicitly self-signed ... found.
  [10/18] openVPN/certs/server X509 certificate - signed by 'openVPN/certs/root' ... found.
  [11/18] passwords:alt random password - 32 bytes ... found.
  [12/18] passwords:permanent random password - 128 bytes, fixed ... found.
  [13/18] passwords:uncrypted random password - 1024 bytes ... found.
  [14/18] passwords:word random password - 64 bytes, fixed ... found.
  [15/18] rsa RSA public/private keypair - 4096 bits, fixed ... found.
  [16/18] rsa-default RSA public/private keypair - 2048 bits ... found.
  [17/18] ssh SSH public/private keypair - 1024 bits ... found.
  [18/18] ssh-default SSH public/private keypair - 2048 bits, fixed ... found.
Completed - Duration: XXX seconds [18 found/0 skipped/0 errors]

EOF

	# Feature: Validate secrets, including signer and key usage
	($pass, $rc, $out) = runs_ok("genesis check-secrets $env_name --validate", "genesis check-secrets --validate runs without error (default secrets stuff)");
	$out =~ s/(Duration:|-) \d+ seconds/$1 XXX seconds/g;
	$out =~ s/expires in (\d+) days \(([^\)]+)\)/expires in $1 days (<timestamp>)/g;
	$out =~ s/ca\.n\d{9}\./ca.n<random>./g;
	matches_utf8 $out, <<EOF, "genesis new correctly created secrets of the correct type and location (default secrets stuff)";
Parsing kit secrets descriptions ... done. - XXX seconds
Retrieving all existing secrets ... done. - XXX seconds

Validating 18 secrets for c-azure-us1-dev under path '/secret/genesis-2.7.0/deployments/dev/azure/us1/':
  [ 1/18] fixed/ca X509 certificate - CA, signed by '/secret/genesis-2.7.0/root_ca' ... valid.
          [✔ ] CA Certificate
          [✔ ] Signed by /secret/genesis-2.7.0/root_ca
          [✔ ] Valid: expires in 1825 days (<timestamp>)
          [✔ ] Modulus Agreement
          [✔ ] Subject Name 'ca.n<random>.fixed'
          [✔ ] Subject Alt Names: ca.n<random>.fixed
          [✔ ] Default CA key usage: server_auth, client_auth, crl_sign, key_cert_sign

  [ 2/18] fixed/server X509 certificate - signed by 'fixed/ca' ... valid.
          [✔ ] Signed by fixed/ca
          [✔ ] Valid: expires in 90 days (<timestamp>)
          [✔ ] Modulus Agreement
          [✔ ] Subject Name 'a really long name with DNS: in it'
          [✔ ] Subject Alt Names: a really long name with DNS: in it
          [✔ ] Default key usage: server_auth, client_auth

  [ 3/18] haproxy/ca X509 certificate - CA, signed by '/secret/genesis-2.7.0/root_ca' ... valid.
          [✔ ] CA Certificate
          [✔ ] Signed by /secret/genesis-2.7.0/root_ca
          [✔ ] Valid: expires in 365 days (<timestamp>)
          [✔ ] Modulus Agreement
          [✔ ] Subject Name 'haProxyCA'
          [✔ ] Subject Alt Names: haProxyCA
          [✔ ] Default CA key usage: server_auth, client_auth, crl_sign, key_cert_sign

  [ 4/18] haproxy/ssl X509 certificate - signed by 'haproxy/ca' ... valid.
          [✔ ] Signed by haproxy/ca
          [✔ ] Valid: expires in 365 days (<timestamp>)
          [✔ ] Modulus Agreement
          [✔ ] Subject Name '*.demo.genesisproject.io'
          [✔ ] Subject Alt Names: *.demo.genesisproject.io, *.system.demo.genesisproject.io, *.run.demo.genesisproject.io, *.uaa.system.demo.genesisproject.io, *.login.system.demo.genesisproject.io
          [✔ ] Specified key usage: client_auth, server_auth

  [ 5/18] top-level/top X509 certificate - CA, signed by '/secret/genesis-2.7.0/root_ca' ... valid.
          [✔ ] CA Certificate
          [✔ ] Signed by /secret/genesis-2.7.0/root_ca
          [✔ ] Valid: expires in 1825 days (<timestamp>)
          [✔ ] Modulus Agreement
          [✔ ] Subject Name 'ca.n<random>.top-level'
          [✔ ] Subject Alt Names: ca.n<random>.top-level
          [✔ ] Default CA key usage: server_auth, client_auth, crl_sign, key_cert_sign

  [ 6/18] secondary/ca X509 certificate - CA, signed by 'top-level/top' ... valid.
          [✔ ] CA Certificate
          [✔ ] Signed by top-level/top
          [✔ ] Valid: expires in 3650 days (<timestamp>)
          [✔ ] Modulus Agreement
          [✔ ] Subject Name 'secondary.ca'
          [✔ ] Subject Alt Names: secondary.ca
          [✔ ] Default CA key usage: server_auth, client_auth, crl_sign, key_cert_sign

  [ 7/18] secondary/server X509 certificate - signed by 'secondary/ca' ... valid.
          [✔ ] Signed by secondary/ca
          [✔ ] Valid: expires in 365 days (<timestamp>)
          [✔ ] Modulus Agreement
          [✔ ] Subject Name 'secondary.server'
          [✔ ] Subject Alt Names: secondary.server
          [✔ ] Specified key usage: client_auth, server_auth

  [ 8/18] top-level/server X509 certificate - signed by 'top-level/top' ... valid.
          [✔ ] Signed by top-level/top
          [✔ ] Valid: expires in 180 days (<timestamp>)
          [✔ ] Modulus Agreement
          [✔ ] Subject Name 'server.example.com'
          [✔ ] Subject Alt Names: server.example.com, system.demo.genesisproject.io, *.server.example.com, *.system.demo.genesisproject.io, 10.10.10.10
          [✔ ] Default key usage: server_auth, client_auth

  [ 9/18] openVPN/certs/root X509 certificate - CA, explicitly self-signed ... valid.
          [✔ ] CA Certificate
          [✔ ] Self-Signed
          [✔ ] Valid: expires in 1825 days (<timestamp>)
          [✔ ] Modulus Agreement
          [✔ ] Subject Name 'ca.openvpn'
          [✔ ] Subject Alt Names: ca.openvpn
          [✔ ] Specified key usage: crl_sign, key_cert_sign

  [10/18] openVPN/certs/server X509 certificate - signed by 'openVPN/certs/root' ... valid.
          [✔ ] Signed by openVPN/certs/root
          [✔ ] Valid: expires in 180 days (<timestamp>)
          [✔ ] Modulus Agreement
          [✔ ] Subject Name 'server.openvpn'
          [✔ ] Subject Alt Names: server.openvpn
          [✔ ] Specified key usage: server_auth, digital_signature, key_encipherment

  [11/18] passwords:alt random password - 32 bytes ... valid.
          [✔ ] 32 characters
          [✔ ] Formatted as base64 in ':alt-base64'

  [12/18] passwords:permanent random password - 128 bytes, fixed ... valid.
          [✔ ] 128 characters

  [13/18] passwords:uncrypted random password - 1024 bytes ... valid.
          [✔ ] 1024 characters
          [✔ ] Formatted as bcrypt in ':crypted'

  [14/18] passwords:word random password - 64 bytes, fixed ... valid.
          [✔ ] 64 characters
          [✔ ] Only uses characters '01'

  [15/18] rsa RSA public/private keypair - 4096 bits, fixed ... valid.
          [✔ ] Valid private key
          [✔ ] Valid public key
          [✔ ] 4096 bit
          [✔ ] Public/Private key agreement

  [16/18] rsa-default RSA public/private keypair - 2048 bits ... valid.
          [✔ ] Valid private key
          [✔ ] Valid public key
          [✔ ] 2048 bit
          [✔ ] Public/Private key agreement

  [17/18] ssh SSH public/private keypair - 1024 bits ... valid.
          [✔ ] Valid private key
          [✔ ] Valid public key
          [✔ ] Public/Private key Agreement
          [✔ ] 1024 bits

  [18/18] ssh-default SSH public/private keypair - 2048 bits, fixed ... valid.
          [✔ ] Valid private key
          [✔ ] Valid public key
          [✔ ] Public/Private key Agreement
          [✔ ] 2048 bits

Completed - Duration: XXX seconds [18 validated/0 skipped/0 errors]

EOF

	# Feature: No --force on rotate
	($pass,$rc,$out) = run_fails "genesis rotate-secrets --force $env_name -y", "genesis fails when --force option is used on rotate-secrets";
	$out =~ s/(Duration:|-) \d+ seconds/$1 XXX seconds/g;
	matches_utf8 $out, <<'EOF', "genesis reports no force option on rotate-secrets";
--force option no longer valid. See `genesis rotate-secrets -h` for more details
EOF

  my $env = Genesis::Top->new('.')->load_env($env_name);
  my ($secrets_old, $err) = $env->vault->all_secrets_for($env);
  my @secret_paths = map {my $p = $_ ; map {[$p, $_]} keys %{$secrets_old->{$_}}} keys %$secrets_old;

	($pass,$rc,$out) = runs_ok "genesis rotate-secrets $env_name -y --filter '/(/ca\$|passwords:)/'", "can rotate certs according to filter";
	$out =~ s/(Duration:|-) \d+ seconds/$1 XXX seconds/g;
	matches_utf8 $out,<<'EOF', "genesis rotate-secrets reports rotated filtered secrets, but not fixed ones";
Parsing kit secrets descriptions ... done. - XXX seconds

Recreating 7 secrets for c-azure-us1-dev under path '/secret/genesis-2.7.0/deployments/dev/azure/us1/':
  [1/7] fixed/ca X509 certificate - CA, signed by '/secret/genesis-2.7.0/root_ca' ... skipped
  [2/7] haproxy/ca X509 certificate - CA, signed by '/secret/genesis-2.7.0/root_ca' ... done.
  [3/7] secondary/ca X509 certificate - CA, signed by 'top-level/top' ... done.
  [4/7] passwords:alt random password - 32 bytes ... done.
  [5/7] passwords:permanent random password - 128 bytes, fixed ... skipped
  [6/7] passwords:uncrypted random password - 1024 bytes ... done.
  [7/7] passwords:word random password - 64 bytes, fixed ... skipped
Completed - Duration: XXX seconds [4 recreated/3 skipped/0 errors]

EOF

	my ($secrets_new, $err2) = $env->vault->all_secrets_for($env);
	my (@different);
	for my $secret_path (@secret_paths) {
		my ($path, $key) = @$secret_path;
		push @different, join(":", $path, $key) if ($secrets_old->{$path}{$key} ne $secrets_new->{$path}{$key});
	}
	my @expected = (
		qw(
			secret/genesis-2.7.0/deployments/dev/azure/us1/haproxy/ca:certificate
			secret/genesis-2.7.0/deployments/dev/azure/us1/haproxy/ca:key
			secret/genesis-2.7.0/deployments/dev/azure/us1/haproxy/ca:crl
			secret/genesis-2.7.0/deployments/dev/azure/us1/haproxy/ca:serial
			secret/genesis-2.7.0/deployments/dev/azure/us1/haproxy/ca:combined
			secret/genesis-2.7.0/deployments/dev/azure/us1/secondary/ca:certificate
			secret/genesis-2.7.0/deployments/dev/azure/us1/secondary/ca:key
			secret/genesis-2.7.0/deployments/dev/azure/us1/secondary/ca:crl
			secret/genesis-2.7.0/deployments/dev/azure/us1/secondary/ca:serial
			secret/genesis-2.7.0/deployments/dev/azure/us1/secondary/ca:combined
			secret/genesis-2.7.0/deployments/dev/azure/us1/passwords:alt
			secret/genesis-2.7.0/deployments/dev/azure/us1/passwords:alt-base64
			secret/genesis-2.7.0/deployments/dev/azure/us1/passwords:uncrypted
			secret/genesis-2.7.0/deployments/dev/azure/us1/passwords:crypted), 

			# This following crl and serial seem to be bumped by safe when something they signed is rotated.
		qw(
			secret/genesis-2.7.0/deployments/dev/azure/us1/top-level/top:crl
			secret/genesis-2.7.0/deployments/dev/azure/us1/top-level/top:serial
			secret/genesis-2.7.0/root_ca:crl
			secret/genesis-2.7.0/root_ca:serial
		)
	);
	cmp_deeply(\@different, bag(@expected), "Only the expected secrets changed (including top-level/top crl and serial)");

	($pass,$rc,$out) = run_fails "genesis check-secrets $env_name --validate", "rotation does not rotate certs signed by changed cas";
	$out =~ s/(Duration:|-) \d+ seconds/$1 XXX seconds/g;
	$out =~ s/expires in (\d+) days \(([^\)]+)\)/expires in $1 days (<timestamp>)/g;
	$out =~ s/ca\.n\d{9}\./ca.n<random>./g;
	matches_utf8 $out, <<'EOF', "genesis add-secrets reports existing secrets";
Parsing kit secrets descriptions ... done. - XXX seconds
Retrieving all existing secrets ... done. - XXX seconds

Validating 18 secrets for c-azure-us1-dev under path '/secret/genesis-2.7.0/deployments/dev/azure/us1/':
  [ 1/18] fixed/ca X509 certificate - CA, signed by '/secret/genesis-2.7.0/root_ca' ... valid.
          [✔ ] CA Certificate
          [✔ ] Signed by /secret/genesis-2.7.0/root_ca
          [✔ ] Valid: expires in 1825 days (<timestamp>)
          [✔ ] Modulus Agreement
          [✔ ] Subject Name 'ca.n<random>.fixed'
          [✔ ] Subject Alt Names: ca.n<random>.fixed
          [✔ ] Default CA key usage: server_auth, client_auth, crl_sign, key_cert_sign

  [ 2/18] fixed/server X509 certificate - signed by 'fixed/ca' ... valid.
          [✔ ] Signed by fixed/ca
          [✔ ] Valid: expires in 90 days (<timestamp>)
          [✔ ] Modulus Agreement
          [✔ ] Subject Name 'a really long name with DNS: in it'
          [✔ ] Subject Alt Names: a really long name with DNS: in it
          [✔ ] Default key usage: server_auth, client_auth

  [ 3/18] haproxy/ca X509 certificate - CA, signed by '/secret/genesis-2.7.0/root_ca' ... valid.
          [✔ ] CA Certificate
          [✔ ] Signed by /secret/genesis-2.7.0/root_ca
          [✔ ] Valid: expires in 365 days (<timestamp>)
          [✔ ] Modulus Agreement
          [✔ ] Subject Name 'haProxyCA'
          [✔ ] Subject Alt Names: haProxyCA
          [✔ ] Default CA key usage: server_auth, client_auth, crl_sign, key_cert_sign

  [ 4/18] haproxy/ssl X509 certificate - signed by 'haproxy/ca' ... failed!
          [✘ ] Signed by haproxy/ca
          [✔ ] Valid: expires in 365 days (<timestamp>)
          [✔ ] Modulus Agreement
          [✔ ] Subject Name '*.demo.genesisproject.io'
          [✔ ] Subject Alt Names: *.demo.genesisproject.io, *.system.demo.genesisproject.io, *.run.demo.genesisproject.io, *.uaa.system.demo.genesisproject.io, *.login.system.demo.genesisproject.io
          [✔ ] Specified key usage: client_auth, server_auth

  [ 5/18] top-level/top X509 certificate - CA, signed by '/secret/genesis-2.7.0/root_ca' ... valid.
          [✔ ] CA Certificate
          [✔ ] Signed by /secret/genesis-2.7.0/root_ca
          [✔ ] Valid: expires in 1825 days (<timestamp>)
          [✔ ] Modulus Agreement
          [✔ ] Subject Name 'ca.n<random>.top-level'
          [✔ ] Subject Alt Names: ca.n<random>.top-level
          [✔ ] Default CA key usage: server_auth, client_auth, crl_sign, key_cert_sign

  [ 6/18] secondary/ca X509 certificate - CA, signed by 'top-level/top' ... valid.
          [✔ ] CA Certificate
          [✔ ] Signed by top-level/top
          [✔ ] Valid: expires in 3650 days (<timestamp>)
          [✔ ] Modulus Agreement
          [✔ ] Subject Name 'secondary.ca'
          [✔ ] Subject Alt Names: secondary.ca
          [✔ ] Default CA key usage: server_auth, client_auth, crl_sign, key_cert_sign

  [ 7/18] secondary/server X509 certificate - signed by 'secondary/ca' ... failed!
          [✘ ] Signed by secondary/ca
          [✔ ] Valid: expires in 365 days (<timestamp>)
          [✔ ] Modulus Agreement
          [✔ ] Subject Name 'secondary.server'
          [✔ ] Subject Alt Names: secondary.server
          [✔ ] Specified key usage: client_auth, server_auth

  [ 8/18] top-level/server X509 certificate - signed by 'top-level/top' ... valid.
          [✔ ] Signed by top-level/top
          [✔ ] Valid: expires in 180 days (<timestamp>)
          [✔ ] Modulus Agreement
          [✔ ] Subject Name 'server.example.com'
          [✔ ] Subject Alt Names: server.example.com, system.demo.genesisproject.io, *.server.example.com, *.system.demo.genesisproject.io, 10.10.10.10
          [✔ ] Default key usage: server_auth, client_auth

  [ 9/18] openVPN/certs/root X509 certificate - CA, explicitly self-signed ... valid.
          [✔ ] CA Certificate
          [✔ ] Self-Signed
          [✔ ] Valid: expires in 1825 days (<timestamp>)
          [✔ ] Modulus Agreement
          [✔ ] Subject Name 'ca.openvpn'
          [✔ ] Subject Alt Names: ca.openvpn
          [✔ ] Specified key usage: crl_sign, key_cert_sign

  [10/18] openVPN/certs/server X509 certificate - signed by 'openVPN/certs/root' ... valid.
          [✔ ] Signed by openVPN/certs/root
          [✔ ] Valid: expires in 180 days (<timestamp>)
          [✔ ] Modulus Agreement
          [✔ ] Subject Name 'server.openvpn'
          [✔ ] Subject Alt Names: server.openvpn
          [✔ ] Specified key usage: server_auth, digital_signature, key_encipherment

  [11/18] passwords:alt random password - 32 bytes ... valid.
          [✔ ] 32 characters
          [✔ ] Formatted as base64 in ':alt-base64'

  [12/18] passwords:permanent random password - 128 bytes, fixed ... valid.
          [✔ ] 128 characters

  [13/18] passwords:uncrypted random password - 1024 bytes ... valid.
          [✔ ] 1024 characters
          [✔ ] Formatted as bcrypt in ':crypted'

  [14/18] passwords:word random password - 64 bytes, fixed ... valid.
          [✔ ] 64 characters
          [✔ ] Only uses characters '01'

  [15/18] rsa RSA public/private keypair - 4096 bits, fixed ... valid.
          [✔ ] Valid private key
          [✔ ] Valid public key
          [✔ ] 4096 bit
          [✔ ] Public/Private key agreement

  [16/18] rsa-default RSA public/private keypair - 2048 bits ... valid.
          [✔ ] Valid private key
          [✔ ] Valid public key
          [✔ ] 2048 bit
          [✔ ] Public/Private key agreement

  [17/18] ssh SSH public/private keypair - 1024 bits ... valid.
          [✔ ] Valid private key
          [✔ ] Valid public key
          [✔ ] Public/Private key Agreement
          [✔ ] 1024 bits

  [18/18] ssh-default SSH public/private keypair - 2048 bits, fixed ... valid.
          [✔ ] Valid private key
          [✔ ] Valid public key
          [✔ ] Public/Private key Agreement
          [✔ ] 2048 bits

Failed - Duration: XXX seconds [16 validated/0 skipped/2 errors]

EOF

	# Feature: Rotate failed certificates
  #runs_ok("safe rm -f $v/top-level/top:certificate", "removed top-level/top:certificate for testing");
  runs_ok("safe gen -l 64 -p 12 $v/passwords:word", "regenerated passwords:word for testing");
	runs_ok("safe ssh 1024 $v/rsa", "regenerated rsa for testing");

  ($secrets_old, $err) = $env->vault->all_secrets_for($env);
  @secret_paths = map {my $p = $_ ; map {[$p, $_]} keys %{$secrets_old->{$_}}} keys %$secrets_old;

	$cmd = Expect->new();
	$cmd->log_stdout(0);
	$cmd->spawn("genesis rotate-secrets  $env_name --failed ");
	(undef, my $error, undef, $out) = $cmd->expect(300,"Type 'yes' to recreate these secrets >");

  is($error, undef, "No error or timeout encountered waiting to be asked to recreate secrets");
	$out =~ s/\e\[2K/<clear-line>/g;
	$out =~ s/\r\n/\n/g;
	$out =~ s/\r/<cr>\n/g;
  $out =~ s/'[12]{64}'/'<[12]{64}>'/g;
	$pass = matches_utf8 $out, <<EOF, "genesis lists the expected failed secrets to be recreated";
Parsing kit secrets descriptions ... <cr>
<clear-line>Retrieving all existing secrets ... <cr>
<clear-line>
Checking for failed or missing secrets for $env_name under path '$secrets_mount$secrets_path/':
  [ 1/18] fixed/ca X509 certificate ... <cr>
<clear-line>  [ 2/18] fixed/server X509 certificate ... <cr>
<clear-line>  [ 3/18] haproxy/ca X509 certificate ... <cr>
<clear-line>  [ 4/18] haproxy/ssl X509 certificate ... failed!
          [✘ ] Signed by haproxy/ca

<cr>
<clear-line>  [ 5/18] top-level/top X509 certificate ... <cr>
<clear-line>  [ 6/18] secondary/ca X509 certificate ... <cr>
<clear-line>  [ 7/18] secondary/server X509 certificate ... failed!
          [✘ ] Signed by secondary/ca

<cr>
<clear-line>  [ 8/18] top-level/server X509 certificate ... <cr>
<clear-line>  [ 9/18] openVPN/certs/root X509 certificate ... <cr>
<clear-line>  [10/18] openVPN/certs/server X509 certificate ... <cr>
<clear-line>  [11/18] passwords:alt random password ... <cr>
<clear-line>  [12/18] passwords:permanent random password ... <cr>
<clear-line>  [13/18] passwords:uncrypted random password ... <cr>
<clear-line>  [14/18] passwords:word random password ... failed!
          [✘ ] Only uses characters '01' (found invalid characters in '<[12]{64}>')

<cr>
<clear-line>  [15/18] rsa RSA public/private keypair ... failed!
          [✘ ] Valid public key

<cr>
<clear-line>  [16/18] rsa-default RSA public/private keypair ... <cr>
<clear-line>  [17/18] ssh SSH public/private keypair ... <cr>
<clear-line>  [18/18] ssh-default SSH public/private keypair ... <cr>
<clear-line>Found 4 failed secrets
<cr>
<clear-line>
[WARNING] The following secrets will be recreated:
    • haproxy/ssl
    • secondary/server
    • passwords:word
    • rsa

EOF

  if ($pass && !$error) {
    $cmd->send("yes\n");
    expect_exit $cmd, 0, "genesis recreates a new environment and auto-generates certificates";
    $out = $cmd->before;
    $out =~ s/\e\[2K/<clear-line>/g;
    $out =~ s/\r\n/\n/g;
    $out =~ s/\r/<cr>\n/g;
    $out =~ s/(Duration:|-) \d+ seconds/$1 XXX seconds/g;
    matches_utf8 $out, <<EOF, "genesis rotate-secrets rotates failed but skips fixed secrets";
 yes

Recreating 4 secrets for $env_name under path '$secrets_mount$secrets_path/':
  [1/4] haproxy/ssl X509 certificate ... <cr>
<clear-line>  [2/4] secondary/server X509 certificate ... <cr>
<clear-line>  [3/4] passwords:word random password ... skipped
<cr>
<clear-line>  [4/4] rsa RSA public/private keypair ... skipped
<cr>
<clear-line>Completed - Duration: XXX seconds [2 recreated/2 skipped/0 errors]

EOF

    $out = combined_from {
      $cmd = Expect->new();
      $cmd->log_stdout(1);
      $cmd->spawn("GENESIS_NO_UTF8=1 genesis check-secrets $env_name --validate");
      expect_ok $cmd, "[16 validated/0 skipped/2 errors]";
      expect_exit $cmd, 1, "genesis check-secrets after rotate failed - expect fixed secrets still errored";
    };
    $out =~ s/\e\[2K/<clear-line>/g;
    $out =~ s/\r\n/\n/g;
    $out =~ s/\r/<cr>\n/g;
    $out =~ s/'[12]{64}'/'<[12]{64}>'/g;
    $out =~ s/(Duration:|-) \d+ seconds/$1 XXX seconds/g;
    matches_utf8 $out,<<EOF, "genesis rotate-secrets reports rotated filtered secrets, but not fixed ones";
Parsing kit secrets descriptions ... <cr>
<clear-line>Retrieving all existing secrets ... <cr>
<clear-line>
Validating 18 secrets for $env_name under path '$secrets_mount$secrets_path/':
  [ 1/18] fixed/ca X509 certificate ... <cr>
<clear-line>  [ 2/18] fixed/server X509 certificate ... <cr>
<clear-line>  [ 3/18] haproxy/ca X509 certificate ... <cr>
<clear-line>  [ 4/18] haproxy/ssl X509 certificate ... <cr>
<clear-line>  [ 5/18] top-level/top X509 certificate ... <cr>
<clear-line>  [ 6/18] secondary/ca X509 certificate ... <cr>
<clear-line>  [ 7/18] secondary/server X509 certificate ... <cr>
<clear-line>  [ 8/18] top-level/server X509 certificate ... <cr>
<clear-line>  [ 9/18] openVPN/certs/root X509 certificate ... <cr>
<clear-line>  [10/18] openVPN/certs/server X509 certificate ... <cr>
<clear-line>  [11/18] passwords:alt random password ... <cr>
<clear-line>  [12/18] passwords:permanent random password ... <cr>
<clear-line>  [13/18] passwords:uncrypted random password ... <cr>
<clear-line>  [14/18] passwords:word random password ... failed!
          [-] Only uses characters '01' (found invalid characters in '<[12]{64}>')

<cr>
<clear-line>  [15/18] rsa RSA public/private keypair ... failed!
          [-] Valid public key

<cr>
<clear-line>  [16/18] rsa-default RSA public/private keypair ... <cr>
<clear-line>  [17/18] ssh SSH public/private keypair ... <cr>
<clear-line>  [18/18] ssh-default SSH public/private keypair ... <cr>
<clear-line>Failed - Duration: XXX seconds [16 validated/0 skipped/2 errors]

EOF
    ($secrets_new, $err2) = $env->vault->all_secrets_for($env);
    @different = ();
    for my $secret_path (@secret_paths) {
      my ($path, $key) = @$secret_path;
      push @different, join(":", $path, $key) if ($secrets_old->{$path}{$key} ne $secrets_new->{$path}{$key});
    }
    my @expected = (
      qw(
        secret/genesis-2.7.0/deployments/dev/azure/us1/haproxy/ca:crl
        secret/genesis-2.7.0/deployments/dev/azure/us1/haproxy/ca:serial
        secret/genesis-2.7.0/deployments/dev/azure/us1/haproxy/ssl:certificate
        secret/genesis-2.7.0/deployments/dev/azure/us1/haproxy/ssl:combined
        secret/genesis-2.7.0/deployments/dev/azure/us1/haproxy/ssl:key
        secret/genesis-2.7.0/deployments/dev/azure/us1/secondary/ca:crl
        secret/genesis-2.7.0/deployments/dev/azure/us1/secondary/ca:serial
        secret/genesis-2.7.0/deployments/dev/azure/us1/secondary/server:certificate
        secret/genesis-2.7.0/deployments/dev/azure/us1/secondary/server:combined
        secret/genesis-2.7.0/deployments/dev/azure/us1/secondary/server:key
      )
    );
    cmp_deeply(\@different, bag(@expected), "Only the expected secrets changed (including top-level/top crl and serial)");
  } else {
    diag "Cowardly refusing to proceed - killing genesis rotate-secrets process";
    $cmd->hard_close();
  }

  # Feature: Remove secrets
  # Feature: Remove secrets - can remove fixed secrets
  # Feature: Remove secrets - can remove failed secrets
  ($pass,$rc,$out) = runs_ok "GENESIS_NO_UTF8=1 genesis remove-secrets $env_name -y -X", "Remove all failed secrets";
  $out =~ s/(Duration:|-) \d+ seconds/$1 XXX seconds/g;
  $out =~ s/'[12]{64}'/'<[12]{64}>'/g;
  eq_or_diff $out, <<EOF, "genesis add-secrets reports existing secrets";
Parsing kit secrets descriptions ... done. - XXX seconds
Retrieving all existing secrets ... done. - XXX seconds

Checking for failed secrets for $env_name under path '$secrets_mount$secrets_path/':
  [ 1/18] fixed/ca X509 certificate - CA, signed by '/secret/genesis-2.7.0/root_ca' ... valid.
  [ 2/18] fixed/server X509 certificate - signed by 'fixed/ca' ... valid.
  [ 3/18] haproxy/ca X509 certificate - CA, signed by '/secret/genesis-2.7.0/root_ca' ... valid.
  [ 4/18] haproxy/ssl X509 certificate - signed by 'haproxy/ca' ... valid.
  [ 5/18] top-level/top X509 certificate - CA, signed by '/secret/genesis-2.7.0/root_ca' ... valid.
  [ 6/18] secondary/ca X509 certificate - CA, signed by 'top-level/top' ... valid.
  [ 7/18] secondary/server X509 certificate - signed by 'secondary/ca' ... valid.
  [ 8/18] top-level/server X509 certificate - signed by 'top-level/top' ... valid.
  [ 9/18] openVPN/certs/root X509 certificate - CA, explicitly self-signed ... valid.
  [10/18] openVPN/certs/server X509 certificate - signed by 'openVPN/certs/root' ... valid.
  [11/18] passwords:alt random password - 32 bytes ... valid.
  [12/18] passwords:permanent random password - 128 bytes, fixed ... valid.
  [13/18] passwords:uncrypted random password - 1024 bytes ... valid.
  [14/18] passwords:word random password - 64 bytes, fixed ... failed!
          [+] 64 characters
          [-] Only uses characters '01' (found invalid characters in '<[12]{64}>')

  [15/18] rsa RSA public/private keypair - 4096 bits, fixed ... failed!
          [+] Valid private key
          [-] Valid public key

  [16/18] rsa-default RSA public/private keypair - 2048 bits ... valid.
  [17/18] ssh SSH public/private keypair - 1024 bits ... valid.
  [18/18] ssh-default SSH public/private keypair - 2048 bits, fixed ... valid.
Found 2 failed secrets

Removing 2 secrets for $env_name under path '$secrets_mount$secrets_path/':
  [1/2] passwords:word random password - 64 bytes, fixed ... done.
  [2/2] rsa RSA public/private keypair - 4096 bits, fixed ... done.
Completed - Duration: XXX seconds [2 removed/0 skipped/0 errors]

EOF

  # Feature: Remove secrets - can remove based on filter (interactive mode)
	$cmd = Expect->new();
	$cmd->log_stdout(0);
	$cmd->spawn("genesis remove-secrets  $env_name -F /t/");
	(undef, $error, undef, $out) = $cmd->expect(300,"Type 'yes' to remove these secrets >");

  is($error, undef, "No error or timeout encountered waiting to be asked to recreate secrets");
	$out =~ s/\e\[2K/<clear-line>/g;
	$out =~ s/\r\n/\n/g;
	$out =~ s/\r/<cr>\n/g;
  $out =~ s/'[12]{64}'/'<[12]{64}>'/g;
	$pass = matches_utf8 $out, <<EOF, "genesis lists the expected failed secrets to be recreated";
Parsing kit secrets descriptions ... <cr>
<clear-line><cr>
<clear-line>
[WARNING] The following secrets will be removed:
    • top-level/top
    • top-level/server
    • openVPN/certs/root
    • openVPN/certs/server
    • passwords:alt
    • passwords:alt-base64 (paired with passwords:alt)
    • passwords:permanent
    • passwords:uncrypted
    • passwords:crypted (paired with passwords:uncrypted)
    • rsa-default
    • ssh-default

EOF

  if ($pass && !$error) {
    $cmd->send("yes\n");
    expect_exit $cmd, 0, "genesis remove-secrets based on filter (anything with a t)";
    $out = $cmd->before;
    $out =~ s/\e\[2K/<clear-line>/g;
    $out =~ s/\r\n/\n/g;
    $out =~ s/\r/<cr>\n/g;
    $out =~ s/(Duration:|-) \d+ seconds/$1 XXX seconds/g;
    matches_utf8 $out, <<EOF, "genesis rotate-secrets rotates filtered secrets";
 yes

Removing 9 secrets for $env_name under path '$secrets_mount$secrets_path/':
  [1/9] top-level/top X509 certificate ... <cr>
<clear-line>  [2/9] top-level/server X509 certificate ... <cr>
<clear-line>  [3/9] openVPN/certs/root X509 certificate ... <cr>
<clear-line>  [4/9] openVPN/certs/server X509 certificate ... <cr>
<clear-line>  [5/9] passwords:alt random password ... <cr>
<clear-line>  [6/9] passwords:permanent random password ... <cr>
<clear-line>  [7/9] passwords:uncrypted random password ... <cr>
<clear-line>  [8/9] rsa-default RSA public/private keypair ... <cr>
<clear-line>  [9/9] ssh-default SSH public/private keypair ... <cr>
<clear-line>Completed - Duration: XXX seconds [9 removed/0 skipped/0 errors]

EOF
    ($pass, $rc, $out) = run_fails("genesis check-secrets $env_name", "genesis check-secrets confirms removed secrets");
    $out =~ s/(Duration:|-) \d+ seconds/$1 XXX seconds/g;
    matches_utf8 $out, <<EOF, "genesis remove-secrets removed the desired secrets";
Parsing kit secrets descriptions ... done. - XXX seconds
Retrieving all existing secrets ... done. - XXX seconds

Checking 18 secrets for $env_name under path '$secrets_mount$secrets_path/':
  [ 1/18] fixed/ca X509 certificate - CA, signed by '$root_ca_path' ... found.
  [ 2/18] fixed/server X509 certificate - signed by 'fixed/ca' ... found.
  [ 3/18] haproxy/ca X509 certificate - CA, signed by '/secret/genesis-2.7.0/root_ca' ... found.
  [ 4/18] haproxy/ssl X509 certificate - signed by 'haproxy/ca' ... found.
  [ 5/18] top-level/top X509 certificate - CA, signed by '/secret/genesis-2.7.0/root_ca' ... missing!
  [ 6/18] secondary/ca X509 certificate - CA, signed by 'top-level/top' ... found.
  [ 7/18] secondary/server X509 certificate - signed by 'secondary/ca' ... found.
  [ 8/18] top-level/server X509 certificate - signed by 'top-level/top' ... missing!
  [ 9/18] openVPN/certs/root X509 certificate - CA, explicitly self-signed ... missing!
  [10/18] openVPN/certs/server X509 certificate - signed by 'openVPN/certs/root' ... missing!
  [11/18] passwords:alt random password - 32 bytes ... missing!
  [12/18] passwords:permanent random password - 128 bytes, fixed ... missing!
  [13/18] passwords:uncrypted random password - 1024 bytes ... missing!
  [14/18] passwords:word random password - 64 bytes, fixed ... missing!
  [15/18] rsa RSA public/private keypair - 4096 bits, fixed ... missing!
  [16/18] rsa-default RSA public/private keypair - 2048 bits ... missing!
  [17/18] ssh SSH public/private keypair - 1024 bits ... found.
  [18/18] ssh-default SSH public/private keypair - 2048 bits, fixed ... missing!
Failed - Duration: XXX seconds [7 found/0 skipped/11 errors]

EOF
  } else {
    diag "Cowardly refusing to proceed - killing genesis remove-secrets process";
    $cmd->hard_close();
  }


  ($pass, $rc, $out) = runs_ok("genesis add-secrets $env_name", "genesis add the removed secrets");
  $out =~ s/(Duration:|-) \d+ seconds/$1 XXX seconds/g;
  matches_utf8 $out, <<EOF, "genesis add-secrets added the missing secrets";
Parsing kit secrets descriptions ... done. - XXX seconds

Adding 18 secrets for c-azure-us1-dev under path '/secret/genesis-2.7.0/deployments/dev/azure/us1/':
  [ 1/18] fixed/ca X509 certificate - CA, signed by '/secret/genesis-2.7.0/root_ca' ... exists!
  [ 2/18] fixed/server X509 certificate - signed by 'fixed/ca' ... exists!
  [ 3/18] haproxy/ca X509 certificate - CA, signed by '/secret/genesis-2.7.0/root_ca' ... exists!
  [ 4/18] haproxy/ssl X509 certificate - signed by 'haproxy/ca' ... exists!
  [ 5/18] top-level/top X509 certificate - CA, signed by '/secret/genesis-2.7.0/root_ca' ... done.
  [ 6/18] secondary/ca X509 certificate - CA, signed by 'top-level/top' ... exists!
  [ 7/18] secondary/server X509 certificate - signed by 'secondary/ca' ... exists!
  [ 8/18] top-level/server X509 certificate - signed by 'top-level/top' ... done.
  [ 9/18] openVPN/certs/root X509 certificate - CA, explicitly self-signed ... done.
  [10/18] openVPN/certs/server X509 certificate - signed by 'openVPN/certs/root' ... done.
  [11/18] passwords:alt random password - 32 bytes ... done.
  [12/18] passwords:permanent random password - 128 bytes, fixed ... done.
  [13/18] passwords:uncrypted random password - 1024 bytes ... done.
  [14/18] passwords:word random password - 64 bytes, fixed ... done.
  [15/18] rsa RSA public/private keypair - 4096 bits, fixed ... done.
  [16/18] rsa-default RSA public/private keypair - 2048 bits ... done.
  [17/18] ssh SSH public/private keypair - 1024 bits ... exists!
  [18/18] ssh-default SSH public/private keypair - 2048 bits, fixed ... done.
Completed - Duration: XXX seconds [11 added/7 skipped/0 errors]

EOF

  # Feature: Renew ca certs so they are still valid for certs signed by them
  ($secrets_old, $err) = $env->vault->all_secrets_for($env);
  @secret_paths = map {my $p = $_ ; map {[$p, $_]} keys %{$secrets_old->{$_}}} keys %$secrets_old;

  $cmd = Expect->new();
  $cmd->log_stdout(0);
  $cmd->spawn("genesis rotate-secrets $env_name --renew -v -F '/(/ca\$|passwords:)/'");
  (undef, $error, undef, $out) = $cmd->expect(300,"Type 'yes' to renew these secrets >");

  is($error, undef, "No error or timeout encountered waiting to be asked to renew secrets");
  $out =~ s/\e\[2K/<clear-line>/g;
  $out =~ s/\r\n/\n/g;
  $out =~ s/\r/<cr>\n/g;
  $out =~ s/(Duration:|-) \d+ seconds/$1 XXX seconds/g;
  $out =~ s/'[12]{64}'/'<[12]{64}>'/g;
  $pass = matches_utf8 $out, <<EOF, "genesis lists the expected failed secrets to be recreated";
Parsing kit secrets descriptions ... done. - XXX seconds
<cr>
<clear-line>
[WARNING] The following secrets will be renewed:
    • fixed/ca
    • haproxy/ca
    • secondary/ca

EOF

  if ($pass && !$error) {
    $cmd->send("yes\n");
    expect_exit $cmd, 0, "genesis rotate-secrets based on filter (anything with a t) succeeded";
    $out = $cmd->before;
    $out =~ s/\e\[2K/<clear-line>/g;
    $out =~ s/\r\n/\n/g;
    $out =~ s/\r/<cr>\n/g;
    $out =~ s/updated to [^\(]* \(/updated to <date> (/g;
    $out =~ s/(Duration:|-) \d+ seconds/$1 XXX seconds/g;
    matches_utf8 $out, <<EOF, "genesis rotate-secrets rotates filtered secrets";
 yes

Renewing 3 secrets for c-azure-us1-dev under path '/secret/genesis-2.7.0/deployments/dev/azure/us1/':
  [1/3] fixed/ca X509 certificate - CA, signed by '/secret/genesis-2.7.0/root_ca' ... done.
        [✔ ] Expiry updated to <date> (1825 days)

  [2/3] haproxy/ca X509 certificate - CA, signed by '/secret/genesis-2.7.0/root_ca' ... done.
        [✔ ] Expiry updated to <date> (365 days)

  [3/3] secondary/ca X509 certificate - CA, signed by 'top-level/top' ... done.
        [✔ ] Expiry updated to <date> (3650 days)

Completed - Duration: XXX seconds [3 renewed/0 skipped/0 errors]

EOF

    ($secrets_new, $err2) = $env->vault->all_secrets_for($env);
    @different = ();
    for my $secret_path (@secret_paths) {
      my ($path, $key) = @$secret_path;
      push @different, join(":", $path, $key) if ($secrets_old->{$path}{$key} ne $secrets_new->{$path}{$key});
    }
    my @expected = (
      qw(
        secret/genesis-2.7.0/deployments/dev/azure/us1/fixed/ca:certificate
        secret/genesis-2.7.0/deployments/dev/azure/us1/fixed/ca:combined
        secret/genesis-2.7.0/deployments/dev/azure/us1/fixed/ca:crl
        secret/genesis-2.7.0/deployments/dev/azure/us1/haproxy/ca:certificate
        secret/genesis-2.7.0/deployments/dev/azure/us1/haproxy/ca:combined
        secret/genesis-2.7.0/deployments/dev/azure/us1/haproxy/ca:crl
        secret/genesis-2.7.0/deployments/dev/azure/us1/secondary/ca:certificate
        secret/genesis-2.7.0/deployments/dev/azure/us1/secondary/ca:combined
        secret/genesis-2.7.0/deployments/dev/azure/us1/secondary/ca:crl
        secret/genesis-2.7.0/deployments/dev/azure/us1/top-level/top:crl
        secret/genesis-2.7.0/deployments/dev/azure/us1/top-level/top:serial
        secret/genesis-2.7.0/root_ca:crl
        secret/genesis-2.7.0/root_ca:serial
      )
    );
    cmp_deeply(\@different, bag(@expected), "Only the expected secrets changed");

    $out = combined_from {
      $cmd = Expect->new();
      $cmd->log_stdout(1);
      $cmd->spawn("genesis check-secrets $env_name --validate");
      expect_ok $cmd, "[18 validated/0 skipped/0 errors]";
      expect_exit $cmd, 0, "genesis check-secrets --validate without verbosity";
    };
    $out =~ s/\e\[2K/<clear-line>/g;
    $out =~ s/\r\n/\n/g;
    $out =~ s/\r/<cr>\n/g;
    $out =~ s/(Duration:|-) \d+ seconds/$1 XXX seconds/g;
    matches_utf8 $out,<<EOF, "genesis rotate-secrets --renew didn't invalidate any signing chains";
Parsing kit secrets descriptions ... <cr>
<clear-line>Retrieving all existing secrets ... <cr>
<clear-line>
Validating 18 secrets for $env_name under path '$secrets_mount$secrets_path/':
  [ 1/18] fixed/ca X509 certificate ... <cr>
<clear-line>  [ 2/18] fixed/server X509 certificate ... <cr>
<clear-line>  [ 3/18] haproxy/ca X509 certificate ... <cr>
<clear-line>  [ 4/18] haproxy/ssl X509 certificate ... <cr>
<clear-line>  [ 5/18] top-level/top X509 certificate ... <cr>
<clear-line>  [ 6/18] secondary/ca X509 certificate ... <cr>
<clear-line>  [ 7/18] secondary/server X509 certificate ... <cr>
<clear-line>  [ 8/18] top-level/server X509 certificate ... <cr>
<clear-line>  [ 9/18] openVPN/certs/root X509 certificate ... <cr>
<clear-line>  [10/18] openVPN/certs/server X509 certificate ... <cr>
<clear-line>  [11/18] passwords:alt random password ... <cr>
<clear-line>  [12/18] passwords:permanent random password ... <cr>
<clear-line>  [13/18] passwords:uncrypted random password ... <cr>
<clear-line>  [14/18] passwords:word random password ... <cr>
<clear-line>  [15/18] rsa RSA public/private keypair ... <cr>
<clear-line>  [16/18] rsa-default RSA public/private keypair ... <cr>
<clear-line>  [17/18] ssh SSH public/private keypair ... <cr>
<clear-line>  [18/18] ssh-default SSH public/private keypair ... <cr>
<clear-line>Completed - Duration: XXX seconds [18 validated/0 skipped/0 errors]

EOF

  } else {
    diag "Cowardly refusing to proceed - killing genesis rotate-secrets process";
    $cmd->hard_close();
  }

	$env_name = 'c-azure-us1-prod';
	$secrets_mount = '/secret/';
	$secrets_path = 'c/azure/us1/prod/secrets-2.7.0';

	$cmd = Expect->new();
	$cmd->log_stdout($ENV{GENESIS_TRACE} ? 1 : 0);
	$cmd->spawn("genesis new $env_name");

	expect_ok $cmd, [ "What is your base domain?", sub { $_[0]->send("live.genesisproject.io\n"); }];
	expect_exit $cmd, 0, "genesis creates a new environment and auto-generates certificates - default secrets stuff";

	($pass,$rc,$out) = runs_ok("genesis lookup $env_name .");
	lives_ok {$properties = decode_json($out)} "genesis lookup on environment returns parsable json";

	# Feature: Setting the root_ca_path, secrets_mount and secrets_path on genesis new - doesn't store default
	ok !defined($properties->{genesis}{root_ca_path}),  "environment doesn't specify default root ca path";
	ok !defined($properties->{genesis}{secrets_mount}), "environment doesn't specify default secrets mount";
	ok !defined($properties->{genesis}{secrets_path}),  "environment doesn't specify default secrets path";

	($pass, $rc, $out) = runs_ok("genesis check-secrets $env_name", "genesis check-secrets runs without error");
	$out =~ s/(Duration:|-) \d+ seconds/$1 XXX seconds/g;
	matches_utf8 $out, <<EOF, "genesis new correctly created secrets of the correct type and location";
Parsing kit secrets descriptions ... done. - XXX seconds
Retrieving all existing secrets ... done. - XXX seconds

Checking 18 secrets for $env_name under path '$secrets_mount$secrets_path/':
  [ 1/18] fixed/ca X509 certificate - CA, self-signed ... found.
  [ 2/18] fixed/server X509 certificate - signed by 'fixed/ca' ... found.
  [ 3/18] haproxy/ca X509 certificate - CA, self-signed ... found.
  [ 4/18] haproxy/ssl X509 certificate - signed by 'haproxy/ca' ... found.
  [ 5/18] top-level/top X509 certificate - CA, self-signed ... found.
  [ 6/18] secondary/ca X509 certificate - CA, signed by 'top-level/top' ... found.
  [ 7/18] secondary/server X509 certificate - signed by 'secondary/ca' ... found.
  [ 8/18] top-level/server X509 certificate - signed by 'top-level/top' ... found.
  [ 9/18] openVPN/certs/root X509 certificate - CA, explicitly self-signed ... found.
  [10/18] openVPN/certs/server X509 certificate - signed by 'openVPN/certs/root' ... found.
  [11/18] passwords:alt random password - 32 bytes ... found.
  [12/18] passwords:permanent random password - 128 bytes, fixed ... found.
  [13/18] passwords:uncrypted random password - 1024 bytes ... found.
  [14/18] passwords:word random password - 64 bytes, fixed ... found.
  [15/18] rsa RSA public/private keypair - 4096 bits, fixed ... found.
  [16/18] rsa-default RSA public/private keypair - 2048 bits ... found.
  [17/18] ssh SSH public/private keypair - 1024 bits ... found.
  [18/18] ssh-default SSH public/private keypair - 2048 bits, fixed ... found.
Completed - Duration: XXX seconds [18 found/0 skipped/0 errors]

EOF

	$env = Genesis::Top->new('.')->load_env($env_name);
	($secrets_old, $err) = $env->vault->all_secrets_for($env);
	@secret_paths = map {my $p = $_ ; map {[$p, $_]} keys %{$secrets_old->{$_}}} keys %$secrets_old;

	($pass,$rc,$out) = runs_ok "genesis rotate-secrets $env_name -y --filter '/(/server|-default)\$/'", "can rotate certs according to filter";
	$out =~ s/(Duration:|-) \d+ seconds/$1 XXX seconds/g;
	matches_utf8 $out,<<EOF, "genesis rotate-secrets reports rotated filtered secrets, but not fixed ones";
Parsing kit secrets descriptions ... done. - XXX seconds

Recreating 6 secrets for $env_name under path '$secrets_mount$secrets_path/':
  [1/6] fixed/server X509 certificate - signed by 'fixed/ca' ... skipped
  [2/6] secondary/server X509 certificate - signed by 'secondary/ca' ... done.
  [3/6] top-level/server X509 certificate - signed by 'top-level/top' ... done.
  [4/6] openVPN/certs/server X509 certificate - signed by 'openVPN/certs/root' ... done.
  [5/6] rsa-default RSA public/private keypair - 2048 bits ... done.
  [6/6] ssh-default SSH public/private keypair - 2048 bits, fixed ... skipped
Completed - Duration: XXX seconds [4 recreated/2 skipped/0 errors]

EOF

	($secrets_new, $err2) = $env->vault->all_secrets_for($env);
	@different = ();
	for my $secret_path (@secret_paths) {
		my ($path, $key) = @$secret_path;
		push @different, join(":", $path, $key) if ($secrets_old->{$path}{$key} ne $secrets_new->{$path}{$key});
	}
	@expected = (
		qw(
			secret/c/azure/us1/prod/secrets-2.7.0/openVPN/certs/server:certificate
			secret/c/azure/us1/prod/secrets-2.7.0/openVPN/certs/server:combined
			secret/c/azure/us1/prod/secrets-2.7.0/openVPN/certs/server:key
			secret/c/azure/us1/prod/secrets-2.7.0/secondary/server:certificate
			secret/c/azure/us1/prod/secrets-2.7.0/secondary/server:combined
			secret/c/azure/us1/prod/secrets-2.7.0/secondary/server:key
			secret/c/azure/us1/prod/secrets-2.7.0/top-level/server:certificate
			secret/c/azure/us1/prod/secrets-2.7.0/top-level/server:combined
			secret/c/azure/us1/prod/secrets-2.7.0/top-level/server:key

			secret/c/azure/us1/prod/secrets-2.7.0/openVPN/certs/root:crl
			secret/c/azure/us1/prod/secrets-2.7.0/openVPN/certs/root:serial
			secret/c/azure/us1/prod/secrets-2.7.0/secondary/ca:crl
			secret/c/azure/us1/prod/secrets-2.7.0/secondary/ca:serial
			secret/c/azure/us1/prod/secrets-2.7.0/top-level/top:crl
			secret/c/azure/us1/prod/secrets-2.7.0/top-level/top:serial
			secret/c/azure/us1/prod/secrets-2.7.0/rsa-default:private
			secret/c/azure/us1/prod/secrets-2.7.0/rsa-default:public
		)
	);

	cmp_deeply(\@different, bag(@expected), "Only the expected secrets changed");

	$out = combined_from {
		$cmd = Expect->new();
		$cmd->log_stdout(1);
		$cmd->spawn("genesis check-secrets $env_name --validate");
		expect_ok $cmd, "[18 validated/0 skipped/0 errors]";
		expect_exit $cmd, 0, "genesis check-secrets after rotate-secrets with filter";
	};
	$out =~ s/\e\[2K/<clear-line>/g;
  $out =~ s/\r\n/\n/g;
	$out =~ s/\r/<cr>\n/g;
	$out =~ s/(Duration:|-) \d+ seconds/$1 XXX seconds/g;
	matches_utf8 $out,<<EOF, "genesis check-secrets after rotate-secrets with filter: all reports good";
Parsing kit secrets descriptions ... <cr>
<clear-line>Retrieving all existing secrets ... <cr>
<clear-line>
Validating 18 secrets for $env_name under path '$secrets_mount$secrets_path/':
  [ 1/18] fixed/ca X509 certificate ... <cr>
<clear-line>  [ 2/18] fixed/server X509 certificate ... <cr>
<clear-line>  [ 3/18] haproxy/ca X509 certificate ... <cr>
<clear-line>  [ 4/18] haproxy/ssl X509 certificate ... <cr>
<clear-line>  [ 5/18] top-level/top X509 certificate ... <cr>
<clear-line>  [ 6/18] secondary/ca X509 certificate ... <cr>
<clear-line>  [ 7/18] secondary/server X509 certificate ... <cr>
<clear-line>  [ 8/18] top-level/server X509 certificate ... <cr>
<clear-line>  [ 9/18] openVPN/certs/root X509 certificate ... <cr>
<clear-line>  [10/18] openVPN/certs/server X509 certificate ... <cr>
<clear-line>  [11/18] passwords:alt random password ... <cr>
<clear-line>  [12/18] passwords:permanent random password ... <cr>
<clear-line>  [13/18] passwords:uncrypted random password ... <cr>
<clear-line>  [14/18] passwords:word random password ... <cr>
<clear-line>  [15/18] rsa RSA public/private keypair ... <cr>
<clear-line>  [16/18] rsa-default RSA public/private keypair ... <cr>
<clear-line>  [17/18] ssh SSH public/private keypair ... <cr>
<clear-line>  [18/18] ssh-default SSH public/private keypair ... <cr>
<clear-line>Completed - Duration: XXX seconds [18 validated/0 skipped/0 errors]

EOF

	# Knock out some endpoints
	$v = $secrets_mount.$secrets_path;
	runs_ok(
		"safe x509 issue -i $v/openVPN/certs/root -n  *.run.live.genesisproject.io -n something -n *.live.genesisproject.io -t 18d -u server_auth -u timestamping $v/haproxy/ssl",
		"regenerated haproxy/ssl for testing"
	);
	runs_ok(
		"safe x509 issue -i $v/fixed/ca -n 'a really long name with DNS: in it' -t 3m -u no $v/fixed/server",
		"regenerated fixed/server for testing"
	);
	runs_ok("safe set $v/ssh public=\"\$(safe get $v/ssh-default:public)\"", "copied ssh-defaul:public to ssh:public for testing");
	runs_ok("safe rm -f $v/rsa-default:private", "removed rsa-default:private for testing");
	runs_ok("safe rm -f $v/top-level/top:certificate", "removed top-level/top:certificate for testing");
  runs_ok("safe gen -l 64 -p 12 $v/passwords:word", "regenerated passwords:word for testing");
	runs_ok("safe ssh 1024 $v/rsa", "regenerated rsa for testing");

	$out = combined_from {
		$cmd = Expect->new();
		$cmd->log_stdout(1);
		$cmd->spawn("genesis check-secrets $env_name --validate");
		expect_exit $cmd, [1,0], "genesis creates a new environment and auto-generates certificates - default secrets stuff";
	};
	#diag @{[grep {$_ =~ 'Duration'} split($/,$out)]}[0];
	$out =~ s/\e\[2K/<clear-line>/g;
	$out =~ s/\r\n/\n/g;
	$out =~ s/\r/<cr>\n/g;
	$out =~ s/ca\.n\d{9}\./ca.n<random>./g;
	$out =~ s/(Duration:|-) \d+ seconds/$1 XXX seconds/g;
	$out =~ s/'[12]{64}'/'<[12]{64}>'/g;
	matches_utf8 $out,<<EOF, "genesis check-secrets after modifiction to cause failures";
Parsing kit secrets descriptions ... <cr>
<clear-line>Retrieving all existing secrets ... <cr>
<clear-line>
Validating 18 secrets for $env_name under path '$secrets_mount$secrets_path/':
  [ 1/18] fixed/ca X509 certificate ... <cr>
<clear-line>  [ 2/18] fixed/server X509 certificate ... warning!
          [⚠ ] Default key usage (missing: client_auth, server_auth)

<cr>
<clear-line>  [ 3/18] haproxy/ca X509 certificate ... <cr>
<clear-line>  [ 4/18] haproxy/ssl X509 certificate ... failed!
          [✘ ] Signed by haproxy/ca
          [✘ ] Subject Name '*.live.genesisproject.io' (found '*.run.live.genesisproject.io')
          [✘ ] Subject Alt Names (missing: *.login.system.live.genesisproject.io, *.run.live.genesisproject.io, *.system.live.genesisproject.io, *.uaa.system.live.genesisproject.io; extra: *.live.genesisproject.io, something)
          [✘ ] Specified key usage (missing: client_auth; extra: timestamping)

<cr>
<clear-line>  [ 5/18] top-level/top X509 certificate ... missing!
          [✘ ] missing key ':certificate'

<cr>
<clear-line>  [ 6/18] secondary/ca X509 certificate ... failed!
          [✘ ] Signed by top-level/top (specified CA not found - found signed by CN 'ca.n<random>.top-level')

<cr>
<clear-line>  [ 7/18] secondary/server X509 certificate ... <cr>
<clear-line>  [ 8/18] top-level/server X509 certificate ... failed!
          [✘ ] Signed by top-level/top (specified CA not found - found signed by CN 'ca.n<random>.top-level')

<cr>
<clear-line>  [ 9/18] openVPN/certs/root X509 certificate ... <cr>
<clear-line>  [10/18] openVPN/certs/server X509 certificate ... <cr>
<clear-line>  [11/18] passwords:alt random password ... <cr>
<clear-line>  [12/18] passwords:permanent random password ... <cr>
<clear-line>  [13/18] passwords:uncrypted random password ... <cr>
<clear-line>  [14/18] passwords:word random password ... failed!
          [✘ ] Only uses characters '01' (found invalid characters in '<[12]{64}>')

<cr>
<clear-line>  [15/18] rsa RSA public/private keypair ... failed!
          [✘ ] Valid public key

<cr>
<clear-line>  [16/18] rsa-default RSA public/private keypair ... missing!
          [✘ ] missing key ':private'

<cr>
<clear-line>  [17/18] ssh SSH public/private keypair ... failed!
          [✘ ] Public/Private key Agreement
          [✘ ] 1024 bits ( found 2048 bits)

<cr>
<clear-line>  [18/18] ssh-default SSH public/private keypair ... <cr>
<clear-line>Failed - Duration: XXX seconds [9 validated/0 skipped/8 errors/1 warnings]

EOF

	chdir $TOPDIR;
	teardown_vault;
}	;

subtest 'secrets-base' => sub {
	plan skip_all => 'skipping secrets tests because SKIP_SECRETS_TESTS was set'
		if $ENV{SKIP_SECRETS_TESTS};
	plan skip_all => 'secrets-base not selected test'
		if @ARGV && ! grep {$_ eq 'secrets-base'} @ARGV;

	my $vault_target = vault_ok;
	bosh2_cli_ok;
	chdir workdir('redis-deployments') or die;

	reprovision init => 'redis',
				kit => 'omega';

	diag "\rConnecting to the local vault (this may take a while)...";
	expects_ok "new-omega us-east-sandbox";
	system('safe tree');

	my $sec;
	my $v = "secret/us/east/sandbox/omega";

	my $rotated = [qw[
	  test/random:username
	  test/random:password
	  test/random:limited

	  test/ssh/strong:public
	  test/ssh/strong:private
	  test/ssh/strong:fingerprint

	  test/ssh/meh:public
	  test/ssh/meh:private
	  test/ssh/meh:fingerprint

	  test/ssh/weak:public
	  test/ssh/weak:private
	  test/ssh/weak:fingerprint

	  test/rsa/strong:public
	  test/rsa/strong:private

	  test/rsa/meh:public
	  test/rsa/meh:private

	  test/rsa/weak:public
	  test/rsa/weak:private

	  test/fmt/sha512/default:random
	  test/fmt/sha512/default:random-crypt-sha512

	  test/fmt/sha512/at:random
	  test/fmt/sha512/at:cryptonomicon

	  auth/cf/uaa:shared_secret
	]];

	my $removed = [qw[
	  test/random:username

	  test/rsa/strong:public
	  test/rsa/strong:private

	  test/fixed/ssh:public
	  test/fixed/ssh:private
	  test/fixed/ssh:fingerprint

	  test/fmt/sha512/default:random
	  test/fmt/sha512/default:random-crypt-sha512
	]];

	my $fixed = [qw[
	  test/fixed/random:username

	  test/fixed/ssh:public
	  test/fixed/ssh:private
	  test/fixed/ssh:fingerprint

	  test/fixed/rsa:public
	  test/fixed/rsa:private

	  auth/cf/uaa:fixed
	]];

	my %before;
	for (@$rotated, @$fixed) {
	  have_secret "$v/$_";
	  $before{$_} = secret "$v/$_";
	}
	no_secret "$v/auth/github/oauth:shared_secret",
	  "should not have secrets from inactive subkits";

	is length($before{'test/random:username'}), 32,
	  "random secret is generated with correct length";

	is length($before{'test/random:password'}), 109,
	  "random secret is generated with correct length";

	like secret("$v/test/random:limited"), qr/^[a-z]{16}$/, "It is possible to limit chars used for random credentials";

	runs_ok "genesis rotate-secrets us-east-sandbox --no-prompt";
	my %after;
	for (@$rotated, @$fixed) {
	  have_secret "$v/$_";
	  $after{$_} = secret "$v/$_";
	}

	for (@$rotated) {
	  isnt $before{$_}, $after{$_}, "$_ should be rotated";
	}
	for (@$fixed) {
	  is $before{$_}, $after{$_}, "$_ should not be rotated";
	}

	# Test that nothing is missing
	my ($pass,$rc,$msg) = runs_ok "genesis check-secrets us-east-sandbox --verbose";
	unlike $msg, qr/\.\.\. missing/, "No secrets should be missing";
	unlike $msg, qr/\.\.\. error/, "No secrets should be errored";
	matches $msg, qr/\.\.\. found/, "Found secrets should be reported";

	# Test only missing secrets are regenerated
	%before = %after;
	for (@$removed) {
	  runs_ok "safe delete -f $v/$_", "removed $v/$_  for testing";
	  no_secret "$v/$_", "$v/$_ should not exist";
	}
	($pass,$rc,$msg) = run_fails "genesis check-secrets us-east-sandbox", 1;
	$msg =~ s/(Duration:|-) \d+ seconds/$1 XXX seconds/g;
	eq_or_diff $msg, <<EOF, "Only deleted secrets are missing";
Parsing kit secrets descriptions ... done. - XXX seconds
Retrieving all existing secrets ... done. - XXX seconds

Checking 16 secrets for us-east-sandbox under path '/secret/us/east/sandbox/omega/':
  [ 1/16] auth/cf/uaa:fixed random password - 128 bytes, fixed ... found.
  [ 2/16] auth/cf/uaa:shared_secret random password - 128 bytes ... found.
  [ 3/16] test/fixed/random:username random password - 32 bytes, fixed ... found.
  [ 4/16] test/fmt/sha512/at:random random password - 8 bytes ... found.
  [ 5/16] test/fmt/sha512/default:random random password - 8 bytes ... missing!
  [ 6/16] test/random:limited random password - 16 bytes ... found.
  [ 7/16] test/random:password random password - 109 bytes ... found.
  [ 8/16] test/random:username random password - 32 bytes ... missing!
  [ 9/16] test/fixed/rsa RSA public/private keypair - 2048 bits, fixed ... found.
  [10/16] test/rsa/meh RSA public/private keypair - 2048 bits ... found.
  [11/16] test/rsa/strong RSA public/private keypair - 4096 bits ... missing!
  [12/16] test/rsa/weak RSA public/private keypair - 1024 bits ... found.
  [13/16] test/fixed/ssh SSH public/private keypair - 2048 bits, fixed ... missing!
  [14/16] test/ssh/meh SSH public/private keypair - 2048 bits ... found.
  [15/16] test/ssh/strong SSH public/private keypair - 4096 bits ... found.
  [16/16] test/ssh/weak SSH public/private keypair - 1024 bits ... found.
Failed - Duration: XXX seconds [12 found/0 skipped/4 errors]

EOF

	runs_ok "genesis add-secrets us-east-sandbox";
	for (@$rotated, @$fixed) {
	  have_secret "$v/$_";
	  $after{$_} = secret "$v/$_";
	}
	for my $path (@$rotated, @$fixed) {
	  if (grep {$_ eq $path} @$removed) {
		isnt $before{$path}, $after{$path}, "$path should be recreated with a new value";
	  } else {
		is $before{$path}, $after{$path}, "$path should be left unchanged";
	  }
	}

	reprovision kit => 'asksecrets';
	my $cmd = Expect->new();
	#$ENV{GENESIS_TRACE} = 'y';
	$cmd->log_stdout($ENV{GENESIS_TRACE} ? 1 : 0);
	$cmd->spawn("genesis new east-us-sandbox");
	$v = "secret/east/us/sandbox/asksecrets";
	expect_ok $cmd, ['password .*\[hidden\]:', sub { $_[0]->send("my-password\n");}];
	expect_ok $cmd, ['password .*\[confirm\]:',  sub { $_[0]->send("my-password\n");}];
	expect_ok $cmd, ["\\(Enter <CTRL-D> to end\\)", sub {
		$_[0]->send("this\nis\nmulti\nline\ndata\n\x4");
	}];
	expect_exit $cmd, 0, "New environment with prompted secret succeeded";
	#$ENV{GENESIS_TRACE} = '';
	system('safe tree');
	have_secret "$v/admin:password";
	is secret("$v/admin:password"), "my-password", "Admin password was stored properly";
	have_secret "$v/cert:pem";
	is secret("$v/cert:pem"), <<EOF, "Multi-line secret was stored properly";
this
is
multi
line
data
EOF

	reprovision kit => "certificates";

	$cmd = Expect->new();
	$cmd->log_stdout($ENV{GENESIS_TRACE} ? 1 : 0);
	$cmd->spawn("genesis new west-us-sandbox");
	$v = "secret/west/us/sandbox/certificates";
	expect_ok $cmd, [ "Generate all the certificates?", sub { $_[0]->send("yes\n"); }];
	expect_ok $cmd, [ "What is your base domain?", sub { $_[0]->send("cf.example.com\n"); }];
	expect_exit $cmd, 0, "genesis creates a new environment and auto-generates certificates";

	have_secret "$v/auto-generated-certs-a/ca:certificate";
	my $x509 = qx(safe get $v/auto-generated-certs-a/ca:certificate | openssl x509 -inform pem -text);
	like $x509, qr/Issuer: CN\s*=\s*ca\.n\d+\.auto-generated-certs-a/m, "CA cert is self-signed";
	like $x509, qr/Subject: CN\s*=\s*ca\.n\d+\.auto-generated-certs-a/m, "CA cert is self-signed";

	have_secret "$v/auto-generated-certs-a/server:certificate";
	$x509 = qx(safe get $v/auto-generated-certs-a/server:certificate | openssl x509 -inform pem -text);
	like $x509, qr/Issuer: CN\s*=\s*ca\.n\d+\.auto-generated-certs-a/m, "server cert is signed by the CA";
	like $x509, qr/Subject: CN\s*=\s*server\.example\.com/m, "server cert has correct CN";
	like $x509, qr/DNS:$_/m, "server cert has SAN for $_"
	  for qw/server\.example\.com \*\.server\.example\.com \*\.system\.cf\.example\.com/;
	like $x509, qr/IP Address:10\.10\.10\.10/m, "server cert has an IP SAN for 10.10.10.10";

	have_secret "$v/auto-generated-certs-a/server:key";
	like secret("$v/auto-generated-certs-a/server:key"), qr/----BEGIN RSA PRIVATE KEY----/,
		"server private key looks like an rsa private key";

	have_secret "$v/auto-generated-certs-b/ca:certificate";
	my $ca_a = secret "$v/auto-generated-certs-a/ca:certificate";
	my $ca_b = secret "$v/auto-generated-certs-b/ca:certificate";
	isnt $ca_a, $ca_b, "CA for auto-generated-certs-a is different from that for auto-generated-certs-b";

	have_secret "$v/auto-generated-certs-b/server:certificate";
	$x509 = qx(safe get $v/auto-generated-certs-b/server:certificate | openssl x509 -inform pem -text);
	like $x509, qr/Issuer: CN\s*=ca\.asdf\.com/m, "server B cert is signed by the CA from auto-generated-certs-b";

	$cmd = Expect->new();
	$cmd->log_stdout($ENV{GENESIS_TRACE} ? 1 : 0);
	$cmd->spawn("genesis new north-us-sandbox");
	$v = "secret/north/us/sandbox/certificates";
	expect_ok $cmd, [ "Generate all the certificates?", sub { $_[0]->send("no\n"); }];
	expect_ok $cmd, [ "What is your base domain?", sub { $_[0]->send("cf.example.com\n"); }];
	expect_exit $cmd, 0, "genesis creates a new environment and doesn't create new certificates from ignored submodules";
	no_secret "$v/auto-generated-certs-b/ca";
	no_secret "$v/auto-generated-certs-b/server";

	$v = "secret/west/us/sandbox/certificates";
	runs_ok "safe delete -Rf $v", "clean up certs for rotation testing";
	no_secret "$v/auto-generated-certs-a/ca:certificate";
	($pass,$rc,$msg) = run_fails "genesis check-secrets west-us-sandbox", 1;
	$msg =~ s/(Duration:|-) \d+ seconds/$1 XXX seconds/g;
	eq_or_diff $msg, <<'EOF', "Removed certs should be missing";
Parsing kit secrets descriptions ... done. - XXX seconds
Retrieving all existing secrets ... done. - XXX seconds

Checking 6 secrets for west-us-sandbox under path '/secret/west/us/sandbox/certificates/':
  [1/6] auto-generated-certs-a/ca X509 certificate - CA, self-signed ... missing!
  [2/6] auto-generated-certs-a/server X509 certificate - signed by 'auto-generated-certs-a/ca' ... missing!
  [3/6] auto-generated-certs-b/ca X509 certificate - CA, self-signed ... missing!
  [4/6] auto-generated-certs-b/server X509 certificate - signed by 'auto-generated-certs-b/ca' ... missing!
  [5/6] fixed/ca X509 certificate - CA, self-signed ... missing!
  [6/6] fixed/server X509 certificate - signed by 'fixed/ca' ... missing!
Failed - Duration: XXX seconds [0 found/0 skipped/6 errors]

EOF
	runs_ok "genesis rotate-secrets west-us-sandbox -y", "genesis creates-secrets our certs";
	have_secret "$v/auto-generated-certs-a/server:certificate";
	my $cert = secret "$v/auto-generated-certs-a/server:certificate";
	have_secret "$v/auto-generated-certs-a/ca:certificate";
	my $ca = secret "$v/auto-generated-certs-a/ca:certificate";

	sub get_cert_validity {
		use Time::Piece;
		my ($info) = @_;
		my $pattern = "%b%n%d %H:%M:%S %Y";
		my @i = $info =~ qr/Not Before:\s(.*\s+\d{4})\s+([^\n\r]*)\s+Not After\s+:\s(.*\s+\d{4})\s+([^\n\r]*)/m;
		return undef unless $i[1] eq $i[3]; # ensure timezones are the same
		return (Time::Piece->strptime($i[2], $pattern) - Time::Piece->strptime($i[0], $pattern));
	}

	# Check correct TTL
	my $fixed_ca = qx(safe get $v/fixed/ca:certificate | openssl x509 -inform pem -text);
	is get_cert_validity($fixed_ca), (5*365*24*3600), "CA cert has a 5 year validity period";

	# Check CA alternative names and default TTL
	my $auto_b_ca = qx(safe get $v/auto-generated-certs-b/ca:certificate | openssl x509 -inform pem -text);
	like $auto_b_ca, qr/Issuer: CN\s*=\s*ca\.asdf\.com/m, "CA cert is self-signed";
	like $auto_b_ca, qr/Subject: CN\s*=\s*ca\.asdf\.com/m, "CA cert is self-signed";
	like $auto_b_ca, qr/Subject Alternative Name:\s+DNS:ca.asdf.com,\s+IP Address:127.1.2.3\s*$/sm,
	               "CA has correct Subject Alternative Names";

	is get_cert_validity($auto_b_ca), (10*365*24*3600), "CA cert has a default 10 year validity period";


	have_secret "$v/fixed/server:certificate";
	my $fixed_cert = secret "$v/fixed/server:certificate";

	runs_ok "genesis rotate-secrets west-us-sandbox -y", "genesis does secrets rotate the CA";
	have_secret "$v/auto-generated-certs-a/ca:certificate";
	my $new_ca = secret "$v/auto-generated-certs-a/ca:certificate";
	isnt $ca, $new_ca, "CA cert does change under normal secret rotation";

	have_secret "$v/fixed/server:certificate";
	my $new_fixed = secret "$v/fixed/server:certificate";
	is $fixed_cert, $new_fixed, "Fixed certificate doesn't change under normal secret rotation";


	$ca = secret "$v/auto-generated-certs-a/ca:certificate";
	$cert = secret "$v/auto-generated-certs-a/server:certificate";
	($pass,$rc,$msg) = runs_ok "genesis add-secrets west-us-sandbox", "genesis add-secrets doesn't rotate the CA";
	$msg =~ s/(Duration:|-) \d+ seconds/$1 XXX seconds/g;
	eq_or_diff $msg, <<'EOF', "genesis add-secrets reports existing secrets";
Parsing kit secrets descriptions ... done. - XXX seconds

Adding 6 secrets for west-us-sandbox under path '/secret/west/us/sandbox/certificates/':
  [1/6] auto-generated-certs-a/ca X509 certificate - CA, self-signed ... exists!
  [2/6] auto-generated-certs-a/server X509 certificate - signed by 'auto-generated-certs-a/ca' ... exists!
  [3/6] auto-generated-certs-b/ca X509 certificate - CA, self-signed ... exists!
  [4/6] auto-generated-certs-b/server X509 certificate - signed by 'auto-generated-certs-b/ca' ... exists!
  [5/6] fixed/ca X509 certificate - CA, self-signed ... exists!
  [6/6] fixed/server X509 certificate - signed by 'fixed/ca' ... exists!
Completed - Duration: XXX seconds [0 added/6 skipped/0 errors]

EOF

	have_secret "$v/auto-generated-certs-a/ca:certificate";
	$new_ca = secret "$v/auto-generated-certs-a/ca:certificate";
	is $ca, $new_ca, "CA cert doesnt change under normal add secrets";

	have_secret "$v/auto-generated-certs-a/server:certificate";
	my $new_cert = secret "$v/auto-generated-certs-a/server:certificate";
	is $cert, $new_cert, "Certificates do not change if existing";

	runs_ok "genesis rotate-secrets -y west-us-sandbox", "genesis rotates-secrets all certs";
	have_secret "$v/auto-generated-certs-a/server:certificate";
	$new_cert = secret "$v/auto-generated-certs-a/server:certificate";
	isnt $cert, $new_cert, "Certificates are rotated normally";

	chdir $TOPDIR;
	teardown_vault;
};

done_testing;
