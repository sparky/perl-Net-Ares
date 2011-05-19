use strict;
use ExtUtils::MakeMaker;
use ExtUtils::MakeMaker::Config;
use ExtUtils::PkgConfig;
use File::Find;

# you can set those manually if c-ares pkgconfig is not working for you
my %ares = (
	incdir => '',	# /some/path (where ares.h is)
	cflags => '',	# -I/some/path
	libs => '',	# -lcares
	version => ''	# 1.7.4
);

# XXX: some compilers may not support those flags
my $devel_cflags = "-Wall ";
$devel_cflags .= "-Werror -DCALLBACK_TYPECHECK " if -d ".git";

if ( $ares{libs} and $ares{version} ) {
	print "Using manually introduced ares options:\n";
	while ( my ($k, $v) = each %ares ) {
		printf " %8s => %s\n", $k, $v;
	}
} else {
	eval {
		%ares = ExtUtils::PkgConfig->find( 'libcares' );
		$ares{version} = $ares{modversion};
	};
	if ( $@ ) {
		print STDERR "pkg-config libcares failed:\n$@\n\n",
			"c-ares development files do not seem to be available\n",
			"You must install c-ares build this module\n\n";
		print STDERR "NA: Unable to build distribution on this platform.\n";
		exit 0;
	}

	print "Found libcares version $ares{version}\n";
}

my $constant_names;
eval {
	$ares{incdir} = get_ares_incdir();
	$constant_names = get_constants_headers( $ares{cflags},
		$ares{incdir} . "/ares.h"
	);
};
if ( $@ ) {
	die "Cannot extract constants from header files: $@";
}

{
	my $cn = scalar @$constant_names;

	print "-> found $cn constants\n";
}

write_constants( "ares-constants.h.inc", $constant_names );

#write_examples_pod( 'lib/Net/Ares/examples.pod' );

# older perl seems to choke on it, maybe utf8::upgrade would work ?
my $l_ = $] >= 5.010 ? "ł" : "l";
WriteMakefile(
	NAME 		=> 'Net::Ares',
	VERSION_FROM	=> 'lib/Net/Ares.pm',
	ABSTRACT_FROM	=> 'lib/Net/Ares.pm',
	AUTHOR		=> "Przemys${l_}aw Iskra <sparky at pld-linux.org>",
	CCFLAGS		=> $devel_cflags . $ares{cflags},
	LIBS		=> $ares{libs},
	SIGN		=> 1,
	LICENSE		=> 'perl',
	META_MERGE	=> {
		resources => {
			repository => 'https://github.com/sparky/perl-Net-Ares'
		},
	},
	MIN_PERL_VERSION => 5.008001,
	CONFIGURE_REQUIRES => {
		"ExtUtils::MakeMaker" => 0,
		"ExtUtils::MakeMaker::Config" => 0,
		"ExtUtils::PkgConfig" => 0,
		"File::Find" => 0,
	},
	PREREQ_PM => {
		"Test::More" => 0,
		"Test::Pod" => 0,
	},
	depend		=> {
		'Makefile'	=> '$(VERSION_FROM)',
	},
	clean		=> {
		FILES => join " ", qw(ares-*.inc lib/Net/Ares/examples.pod),
	},
	DIR			=> [], # no other Makefile.PL
);

exit 0;


sub get_ares_incdir
{
	my @incpath = (
		( defined $ares{incdir} ? $ares{incdir} : () ),
		( $ares{cflags} =~ /-I(\S+)/g ),
		( "$ares{prefix}/include" ),
		( split /\s+/, $Config{usrinc} ),
		( split /\s+/, $Config{locincpth} ),
		qw(
		/usr/include
		/usr/local/include
		/usr/local/ares/include
		/usr/local/include/ares
		)
	);

	foreach my $inc ( @incpath ) {
		if ( -f $inc . "/ares.h") {
			return $inc;
		}
	}

	die "Cannot find ares.h\n";
}


sub get_constants_headers
{
	my %syms;
	my $cflags = shift;

	foreach my $ares_h ( @_ ) {
		print "Reading $ares_h\n";

		open (H, "<", $ares_h)
			or die "Cannot open $ares_h: ".$!;
		while(<H>) {
			if (/^#define (ARES_[A-Za-z0-9_]+)\s+\S/) {
				$syms{ $1 } = 1;
			}
		}
		close H;
	}

	my @out;
	foreach my $e (sort keys %syms) {
		if ( $e =~ /(^ARES_LIB_INIT_|^ARES_GETSOCK_)/ ) {
			next;
		}
		push @out, $e;
	}

	return \@out;
}

sub write_constants
{
	my $out = shift;
	my $constants = shift;

	print "Writing $out\n";

	open my $foutxs, '>', $out
		or die "Can't create $out: $!\n";

	foreach my $c ( sort @$constants ) {
		printf $foutxs "\t\tIV_CONST( $c ),\n";
	}
}

=later
sub write_examples_pod
{
	my $out = shift;

	print "Writing $out\n";
	open my $o, ">", $out;
	print $o "=head1 NAME\n\n";
	print $o "Net::Curl::examples - sample modules and test code for Net::Curl\n\n";

	foreach my $script ( sort glob "examples/*.pl" ) {
		my $nopod = 0;
		my $code = 1;

		print "<- $script\n";

		open my $fin, '<', $script
			or die "Cannot open $script: $!\n";

		while ( <$fin> ) {
			if ( /^=cut/ ) {
				$code = 1;
				next;
			} elsif ( /^=/ ) {
				$code = 0;
			} elsif ( /^#nopod/ ) {
				$nopod = 1;
				next;
			} elsif ( /^#endnopod/ ) {
				$nopod = 0;
				next;
			} elsif ( $nopod ) {
				next;
			}
			$_ = " " . $_ if $code;
			s/^\t/ /;
			s/\t/    /g;
			s/ +$//;
			print $o $_;
			if ( /^=head1\s/ ) {
				print $o "\n=head4 I<Extracted from C<$script>>\n";
			}
		}

		print $o "\n=cut\n";
	}
}
=cut


sub MY::postamble
{
	return <<'EOM';
.PHONY: testall disttestall
testall:
	TEST_HAS_INTERNETS=1 TEST_AUTHOR=1 TEST_EXTENDED=1 $(MAKE) test

disttestall:
	TEST_HAS_INTERNETS=1 TEST_AUTHOR=1 TEST_EXTENDED=1 $(MAKE) disttest
EOM
}

__END__
package ExtUtils::MM_Unix;

sub all_target {
	my $self = shift;
	return <<'MAKE_EXT';
all :: pure_all manifypods
	$(NOECHO) echo "Module loads OK ?"
	$(PERLRUNINST) -le 'use Net::Curl; print Net::Curl::LIBCURL_VERSION'
	$(NOECHO) $(NOOP)
MAKE_EXT

}


# vim: ts=4:sw=4
