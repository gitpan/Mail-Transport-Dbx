# $Id$

use ExtUtils::MakeMaker;

if (unpack("h*", pack("s", 1)) =~ /01/) {
    $BYTEORDER = "DBX_BIG_ENDIAN";
} elsif (unpack("h*", pack("s", 1)) =~ /^1/) {
    $BYTEORDER = "DBX_LITTLE_ENDIAN";
} else {
    print <<EOERR;
Woah!

Your machine is neither BIG_ENDIAN nor LITTLE_ENDIAN!!
libdbx however is only trained to work with one of these two
byteorders.

I will abort now since this library wont be functional on 
this machine.
EOERR
    exit 1;
}

WriteMakefile(
    NAME   => 'Mail::Transport::Dbx::libdbx',
    SKIP   => [qw(all static static_lib dynamic dynamic_lib)],
    clean  => {'FILES' => 'libdbx$(LIBEEXT)'},
    test   => {'TESTS' => ''},
    DEFINE => "-D$BYTEORDER",
    # if you have problems compiling with the defaults,
    # please uncomment the following three lines and check that
    # they reflect your setup:
    # 'CC'          => 'gcc',
    # 'OPTIMIZE'    => '-O',
);

sub MY::top_targets {
    '
all :: static

static ::       libdbx$(LIB_EXT)

libdbx$(LIB_EXT): $(O_FILES)
	$(AR) cr libdbx$(LIB_EXT) $(O_FILES)
	$(RANLIB) libdbx$(LIB_EXT)

pure_all:
	
';
}


