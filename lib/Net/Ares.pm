package Net::Ares;

use strict;
use Exporter 'import';

our @ISA;
our $VERSION;
BEGIN {
	$VERSION = '0.01';

	my $loaded = 0;

	my $load_xs = sub {
		require XSLoader;
		XSLoader::load( __PACKAGE__, $VERSION );
		$loaded = 1;
	};
	my $load_dyna = sub {
		require DynaLoader;
		@ISA = qw(DynaLoader);
		DynaLoader::bootstrap( __PACKAGE__ );
		$loaded = 1;
	};
	eval { $load_xs->() } if $INC{ "XSLoader.pm" };
	eval { $load_dyna->() } if $INC{ "DynaLoader.pm" } and not $loaded;
	unless ( $loaded ) {
		eval { $load_xs->(); };
		$load_dyna->() if $@;
	}
}

our @EXPORT_OK = grep /^ARES/, keys %{Net::Ares::};
our %EXPORT_TAGS = ( constants => \@EXPORT_OK );

1;

__END__

=head1 NAME

Net::Ares - Perl interface for c-ares library

=head1 SYNOPSIS

 use Net::Ares;
 print $Net::Ares::VERSION;

 my $ver = Net::Ares::version();
 printf "Ares: 0x%06X ($ver)\n", 0+$ver;

=head1 DOCUMENTATION

Net::Ares provides a Perl interface to libcares created with object-oriented
implementations in mind. This documentation contains Perl-specific details
and quirks. For more information consult libcares man pages and documentation
at L<http://c-ares.haxx.se>.

=head1 COPYRIGHT

Copyright (c) 2011 Przemyslaw Iskra <sparky at pld-linux.org>.

This program is free software; you can redistribute it and/or
modify it under the same terms as perl itself.

=cut
