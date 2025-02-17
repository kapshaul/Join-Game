package VCBuildProject;

#
# Package that encapsulates a VCBuild (Visual C++ 2005/2008) project file
#
# src/tools/msvc/VCBuildProject.pm
#

use Carp;
use strict;
use warnings;
use base qw(Project);

no warnings qw(redefine);    ## no critic

sub _new
{
	my $classname = shift;
	my $self      = $classname->SUPER::_new(@_);
	bless($self, $classname);

	$self->{filenameExtension} = '.vcproj';

	return $self;
}

sub WriteHeader
{
	my ($self, $f) = @_;

	print $f <<EOF;
<?xml version="1.0" encoding="Windows-1252"?>
<VisualStudioProject ProjectType="Visual C++" Version="$self->{vcver}" Name="$self->{name}" ProjectGUID="$self->{guid}">
 <Platforms><Platform Name="$self->{platform}"/></Platforms>
 <Configurations>
EOF

	$self->WriteConfiguration(
		$f, 'Debug',
		{
			defs     => "_DEBUG;DEBUG=1",
			wholeopt => 0,
			opt      => 0,
			strpool  => 'false',
			runtime  => 3
		});
	$self->WriteConfiguration(
		$f,
		'Release',
		{
			defs     => "",
			wholeopt => 0,
			opt      => 3,
			strpool  => 'true',
			runtime  => 2
		});
	print $f <<EOF;
 </Configurations>
EOF
	$self->WriteReferences($f);
	return;
}

sub WriteFiles
{
	my ($self, $f) = @_;
	print $f <<EOF;
 <Files>
EOF
	my @dirstack = ();
	my %uniquefiles;
	foreach my $fileNameWithPath (sort keys %{ $self->{files} })
	{
		confess "Bad format filename '$fileNameWithPath'\n"
		  unless ($fileNameWithPath =~ m!^(.*)/([^/]+)\.(c|cpp|y|l|rc)$!);
		my $dir  = $1;
		my $file = $2;

		# Walk backwards down the directory stack and close any dirs
		# we're done with.
		while ($#dirstack >= 0)
		{
			if (join('/', @dirstack) eq
				substr($dir, 0, length(join('/', @dirstack))))
			{
				last if (length($dir) == length(join('/', @dirstack)));
				last
				  if (substr($dir, length(join('/', @dirstack)), 1) eq '/');
			}
			print $f ' ' x $#dirstack . "  </Filter>\n";
			pop @dirstack;
		}

		# Now walk forwards and create whatever directories are needed
		while (join('/', @dirstack) ne $dir)
		{
			my $left = substr($dir, length(join('/', @dirstack)));
			$left =~ s/^\///;
			my @pieces = split /\//, $left;
			push @dirstack, $pieces[0];
			print $f ' ' x $#dirstack
			  . "  <Filter Name=\"$pieces[0]\" Filter=\"\">\n";
		}

		# VC builds do not like file paths with forward slashes.
		my $fileNameWithPathFormatted = $fileNameWithPath;
		$fileNameWithPathFormatted =~ s/\//\\/g;

		print $f ' ' x $#dirstack
		  . "   <File RelativePath=\"$fileNameWithPathFormatted\"";
		if ($fileNameWithPath =~ /\.y$/)
		{
			my $of = $fileNameWithPath;
			$of =~ s/\.y$/.c/;
			$of =~
			  s{^src/pl/plpgsql/src/gram.c$}{src/pl/plpgsql/src/pl_gram.c};
			print $f '>'
			  . $self->GenerateCustomTool(
				'Running bison on ' . $fileNameWithPath,
				"perl src/tools/msvc/pgbison.pl $fileNameWithPath", $of)
			  . '</File>' . "\n";
		}
		elsif ($fileNameWithPath =~ /\.l$/)
		{
			my $of = $fileNameWithPath;
			$of =~ s/\.l$/.c/;
			print $f '>'
			  . $self->GenerateCustomTool(
				'Running flex on ' . $fileNameWithPath,
				"perl src/tools/msvc/pgflex.pl $fileNameWithPath", $of)
			  . '</File>' . "\n";
		}
		elsif (defined($uniquefiles{$file}))
		{

			# File already exists, so fake a new name
			my $obj = $dir;
			$obj =~ s!/!_!g;
			print $f
			  "><FileConfiguration Name=\"Debug|$self->{platform}\"><Tool Name=\"VCCLCompilerTool\" ObjectFile=\".\\debug\\$self->{name}\\$obj"
			  . "_$file.obj\" /></FileConfiguration><FileConfiguration Name=\"Release|$self->{platform}\"><Tool Name=\"VCCLCompilerTool\" ObjectFile=\".\\release\\$self->{name}\\$obj"
			  . "_$file.obj\" /></FileConfiguration></File>\n";
		}
		else
		{
			$uniquefiles{$file} = 1;
			print $f " />\n";
		}
	}
	while ($#dirstack >= 0)
	{
		print $f ' ' x $#dirstack . "  </Filter>\n";
		pop @dirstack;
	}
	print $f <<EOF;
 </Files>
EOF
	return;
}

sub Footer
{
	my ($self, $f) = @_;

	print $f <<EOF;
 <Globals/>
</VisualStudioProject>
EOF
	return;
}

sub WriteConfiguration
{
	my ($self, $f, $cfgname, $p) = @_;
	my $cfgtype =
	  ($self->{type} eq "exe") ? 1 : ($self->{type} eq "dll" ? 2 : 4);
	my $libs = $self->GetAdditionalLinkerDependencies($cfgname, ' ');

	my $targetmachine = $self->{platform} eq 'Win32' ? 1 : 17;

	print $f <<EOF;
  <Configuration Name="$cfgname|$self->{platform}" OutputDirectory=".\\$cfgname\\$self->{name}" IntermediateDirectory=".\\$cfgname\\$self->{name}"
	ConfigurationType="$cfgtype" UseOfMFC="0" ATLMinimizesCRunTimeLibraryUsage="FALSE" CharacterSet="2" WholeProgramOptimization="$p->{wholeopt}">
	<Tool Name="VCCLCompilerTool" Optimization="$p->{opt}"
		AdditionalIncludeDirectories="$self->{prefixincludes}src/include;src/include/port/win32;src/include/port/win32_msvc;$self->{includes}"
		PreprocessorDefinitions="WIN32;_WINDOWS;__WINDOWS__;__WIN32__;EXEC_BACKEND;WIN32_STACK_RLIMIT=4194304;_CRT_SECURE_NO_DEPRECATE;_CRT_NONSTDC_NO_DEPRECATE$self->{defines}$p->{defs}"
		StringPooling="$p->{strpool}"
		RuntimeLibrary="$p->{runtime}" DisableSpecificWarnings="$self->{disablewarnings}"
		AdditionalOptions="/MP"
EOF
	print $f <<EOF;
		AssemblerOutput="0" AssemblerListingLocation=".\\$cfgname\\$self->{name}\\" ObjectFile=".\\$cfgname\\$self->{name}\\"
		ProgramDataBaseFileName=".\\$cfgname\\$self->{name}\\" BrowseInformation="0"
		WarningLevel="3" SuppressStartupBanner="TRUE" DebugInformationFormat="3" CompileAs="0"/>
	<Tool Name="VCLinkerTool" OutputFile=".\\$cfgname\\$self->{name}\\$self->{name}.$self->{type}"
		AdditionalDependencies="$libs"
		LinkIncremental="0" SuppressStartupBanner="TRUE" AdditionalLibraryDirectories="" IgnoreDefaultLibraryNames="libc"
		StackReserveSize="4194304" DisableSpecificWarnings="$self->{disablewarnings}"
		GenerateDebugInformation="TRUE" ProgramDatabaseFile=".\\$cfgname\\$self->{name}\\$self->{name}.pdb"
		GenerateMapFile="FALSE" MapFileName=".\\$cfgname\\$self->{name}\\$self->{name}.map"
		RandomizedBaseAddress="FALSE"
		SubSystem="1" TargetMachine="$targetmachine"
EOF
	if ($self->{disablelinkerwarnings})
	{
		print $f
		  "\t\tAdditionalOptions=\"/ignore:$self->{disablelinkerwarnings}\"\n";
	}
	if ($self->{implib})
	{
		my $l = $self->{implib};
		$l =~ s/__CFGNAME__/$cfgname/g;
		print $f "\t\tImportLibrary=\"$l\"\n";
	}
	if ($self->{def})
	{
		my $d = $self->{def};
		$d =~ s/__CFGNAME__/$cfgname/g;
		print $f "\t\tModuleDefinitionFile=\"$d\"\n";
	}

	print $f "\t/>\n";
	print $f
	  "\t<Tool Name=\"VCLibrarianTool\" OutputFile=\".\\$cfgname\\$self->{name}\\$self->{name}.lib\" IgnoreDefaultLibraryNames=\"libc\" />\n";
	print $f
	  "\t<Tool Name=\"VCResourceCompilerTool\" AdditionalIncludeDirectories=\"src\\include\" />\n";
	if ($self->{builddef})
	{
		print $f
		  "\t<Tool Name=\"VCPreLinkEventTool\" Description=\"Generate DEF file\" CommandLine=\"perl src\\tools\\msvc\\gendef.pl $cfgname\\$self->{name} $self->{platform}\" />\n";
	}
	print $f <<EOF;
  </Configuration>
EOF
	return;
}

sub WriteReferences
{
	my ($self, $f) = @_;
	print $f " <References>\n";
	foreach my $ref (@{ $self->{references} })
	{
		print $f
		  "  <ProjectReference ReferencedProjectIdentifier=\"$ref->{guid}\" Name=\"$ref->{name}\" />\n";
	}
	print $f " </References>\n";
	return;
}

sub GenerateCustomTool
{
	my ($self, $desc, $tool, $output, $cfg) = @_;
	if (!defined($cfg))
	{
		return $self->GenerateCustomTool($desc, $tool, $output, 'Debug')
		  . $self->GenerateCustomTool($desc, $tool, $output, 'Release');
	}
	return
	  "<FileConfiguration Name=\"$cfg|$self->{platform}\"><Tool Name=\"VCCustomBuildTool\" Description=\"$desc\" CommandLine=\"$tool\" AdditionalDependencies=\"\" Outputs=\"$output\" /></FileConfiguration>";
}

package VC2005Project;

#
# Package that encapsulates a Visual C++ 2005 project file
#

use strict;
use warnings;
use base qw(VCBuildProject);

no warnings qw(redefine);    ## no critic

sub new
{
	my $classname = shift;
	my $self      = $classname->SUPER::_new(@_);
	bless($self, $classname);

	$self->{vcver} = '8.00';

	return $self;
}

package VC2008Project;

#
# Package that encapsulates a Visual C++ 2008 project file
#

use strict;
use warnings;
use base qw(VCBuildProject);

no warnings qw(redefine);    ## no critic

sub new
{
	my $classname = shift;
	my $self      = $classname->SUPER::_new(@_);
	bless($self, $classname);

	$self->{vcver} = '9.00';

	return $self;
}

1;
