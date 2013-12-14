

use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME         => 'Web::Sitemap',
    VERSION_FROM => 'lib/Web/Sitemap.pm', # finds \$VERSION
    AUTHOR       => 'Mikhail N Bogdanov (bogdanovmn@gmail.com)',
    ABSTRACT     => 'Create sitemap files',
    PREREQ_PM    => {
                     'Test::Simple' => 0.44,
                    },
);
