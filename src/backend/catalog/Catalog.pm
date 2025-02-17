#----------------------------------------------------------------------
#
# Catalog.pm
#    Perl module that extracts info from catalog files into Perl
#    data structures
#
# Portions Copyright (c) 1996-2018, PostgreSQL Global Development Group
# Portions Copyright (c) 1994, Regents of the University of California
#
# src/backend/catalog/Catalog.pm
#
#----------------------------------------------------------------------

package Catalog;

use strict;
use warnings;

use File::Compare;


# Parses a catalog header file into a data structure describing the schema
# of the catalog.
sub ParseHeader
{
	my $input_file = shift;

	# There are a few types which are given one name in the C source, but a
	# different name at the SQL level.  These are enumerated here.
	my %RENAME_ATTTYPE = (
		'int16'         => 'int2',
		'int32'         => 'int4',
		'int64'         => 'int8',
		'Oid'           => 'oid',
		'NameData'      => 'name',
		'TransactionId' => 'xid',
		'XLogRecPtr'    => 'pg_lsn');

	my %catalog;
	my $declaring_attributes = 0;
	my $is_varlen            = 0;
	my $is_client_code       = 0;

	$catalog{columns}     = [];
	$catalog{toasting}    = [];
	$catalog{indexing}    = [];
	$catalog{client_code} = [];

	open(my $ifh, '<', $input_file) || die "$input_file: $!";

	# Scan the input file.
	while (<$ifh>)
	{

		# Set appropriate flag when we're in certain code sections.
		if (/^#/)
		{
			$is_varlen = 1 if /^#ifdef\s+CATALOG_VARLEN/;
			if (/^#ifdef\s+EXPOSE_TO_CLIENT_CODE/)
			{
				$is_client_code = 1;
				next;
			}
			next if !$is_client_code;
		}

		if (!$is_client_code)
		{
			# Strip C-style comments.
			s;/\*(.|\n)*\*/;;g;
			if (m;/\*;)
			{

				# handle multi-line comments properly.
				my $next_line = <$ifh>;
				die "$input_file: ends within C-style comment\n"
				  if !defined $next_line;
				$_ .= $next_line;
				redo;
			}

			# Strip useless whitespace and trailing semicolons.
			chomp;
			s/^\s+//;
			s/;\s*$//;
			s/\s+/ /g;
		}

		# Push the data into the appropriate data structure.
		if (/^DECLARE_TOAST\(\s*(\w+),\s*(\d+),\s*(\d+)\)/)
		{
			push @{ $catalog{toasting} },
			  { parent_table => $1, toast_oid => $2, toast_index_oid => $3 };
		}
		elsif (/^DECLARE_(UNIQUE_)?INDEX\(\s*(\w+),\s*(\d+),\s*(.+)\)/)
		{
			push @{ $catalog{indexing} },
			  {
				is_unique => $1 ? 1 : 0,
				index_name => $2,
				index_oid  => $3,
				index_decl => $4
			  };
		}
		elsif (/^CATALOG\((\w+),(\d+),(\w+)\)/)
		{
			$catalog{catname}            = $1;
			$catalog{relation_oid}       = $2;
			$catalog{relation_oid_macro} = $3;

			$catalog{bootstrap} = /BKI_BOOTSTRAP/ ? ' bootstrap' : '';
			$catalog{shared_relation} =
			  /BKI_SHARED_RELATION/ ? ' shared_relation' : '';
			$catalog{without_oids} =
			  /BKI_WITHOUT_OIDS/ ? ' without_oids' : '';
			if (/BKI_ROWTYPE_OID\((\d+),(\w+)\)/)
			{
				$catalog{rowtype_oid}        = $1;
				$catalog{rowtype_oid_clause} = " rowtype_oid $1";
				$catalog{rowtype_oid_macro}  = $2;
			}
			else
			{
				$catalog{rowtype_oid}        = '';
				$catalog{rowtype_oid_clause} = '';
				$catalog{rowtype_oid_macro}  = '';
			}
			$catalog{schema_macro} = /BKI_SCHEMA_MACRO/ ? 1 : 0;
			$declaring_attributes = 1;
		}
		elsif ($is_client_code)
		{
			if (/^#endif/)
			{
				$is_client_code = 0;
			}
			else
			{
				push @{ $catalog{client_code} }, $_;
			}
		}
		elsif ($declaring_attributes)
		{
			next if (/^{|^$/);
			if (/^}/)
			{
				$declaring_attributes = 0;
			}
			else
			{
				my %column;
				my @attopts = split /\s+/, $_;
				my $atttype = shift @attopts;
				my $attname = shift @attopts;
				die "parse error ($input_file)"
				  unless ($attname and $atttype);

				if (exists $RENAME_ATTTYPE{$atttype})
				{
					$atttype = $RENAME_ATTTYPE{$atttype};
				}

				# If the C name ends with '[]' or '[digits]', we have
				# an array type, so we discard that from the name and
				# prepend '_' to the type.
				if ($attname =~ /(\w+)\[\d*\]/)
				{
					$attname = $1;
					$atttype = '_' . $atttype;
				}

				$column{type}      = $atttype;
				$column{name}      = $attname;
				$column{is_varlen} = 1 if $is_varlen;

				foreach my $attopt (@attopts)
				{
					if ($attopt eq 'BKI_FORCE_NULL')
					{
						$column{forcenull} = 1;
					}
					elsif ($attopt eq 'BKI_FORCE_NOT_NULL')
					{
						$column{forcenotnull} = 1;
					}

					# We use quotes for values like \0 and \054, to
					# make sure all compilers and syntax highlighters
					# can recognize them properly.
					elsif ($attopt =~ /BKI_DEFAULT\(['"]?([^'"]+)['"]?\)/)
					{
						$column{default} = $1;
					}
					elsif ($attopt =~ /BKI_LOOKUP\((\w+)\)/)
					{
						$column{lookup} = $1;
					}
					else
					{
						die
						  "unknown or misformatted column option $attopt on column $attname";
					}

					if ($column{forcenull} and $column{forcenotnull})
					{
						die "$attname is forced both null and not null";
					}
				}
				push @{ $catalog{columns} }, \%column;
			}
		}
	}
	close $ifh;
	return \%catalog;
}

# Parses a file containing Perl data structure literals, returning live data.
#
# The parameter $preserve_formatting needs to be set for callers that want
# to work with non-data lines in the data files, such as comments and blank
# lines. If a caller just wants to consume the data, leave it unset.
sub ParseData
{
	my ($input_file, $schema, $preserve_formatting) = @_;

	open(my $ifd, '<', $input_file) || die "$input_file: $!";
	$input_file =~ /(\w+)\.dat$/
	  or die "Input file $input_file needs to be a .dat file.\n";
	my $catname = $1;
	my $data    = [];

	# Scan the input file.
	while (<$ifd>)
	{
		my $hash_ref;

		if (/{/)
		{
			# Capture the hash ref
			# NB: Assumes that the next hash ref can't start on the
			# same line where the present one ended.
			# Not foolproof, but we shouldn't need a full parser,
			# since we expect relatively well-behaved input.

			# Quick hack to detect when we have a full hash ref to
			# parse. We can't just use a regex because of values in
			# pg_aggregate and pg_proc like '{0,0}'.  This will need
			# work if we ever need to allow unbalanced braces within
			# a field value.
			my $lcnt = tr/{//;
			my $rcnt = tr/}//;

			if ($lcnt == $rcnt)
			{
				# We're treating the input line as a piece of Perl, so we
				# need to use string eval here. Tell perlcritic we know what
				# we're doing.
				eval '$hash_ref = ' . $_;   ## no critic (ProhibitStringyEval)
				if (!ref $hash_ref)
				{
					die "$input_file: error parsing line $.:\n$_\n";
				}

				# Annotate each hash with the source line number.
				$hash_ref->{line_number} = $.;

				# Expand tuples to their full representation.
				AddDefaultValues($hash_ref, $schema, $catname);
			}
			else
			{
				my $next_line = <$ifd>;
				die "$input_file: file ends within Perl hash\n"
				  if !defined $next_line;
				$_ .= $next_line;
				redo;
			}
		}

		# If we found a hash reference, keep it.
		# Only keep non-data strings if we
		# are told to preserve formatting.
		if (defined $hash_ref)
		{
			push @$data, $hash_ref;
		}
		elsif ($preserve_formatting)
		{
			push @$data, $_;
		}
	}
	close $ifd;
	return $data;
}

# Fill in default values of a record using the given schema.
# It's the caller's responsibility to specify other values beforehand.
sub AddDefaultValues
{
	my ($row, $schema, $catname) = @_;
	my @missing_fields;

	# Compute special-case column values.
	# Note: If you add new cases here, you must also teach
	# strip_default_values() in include/catalog/reformat_dat_file.pl
	# to delete them.
	if ($catname eq 'pg_proc')
	{
		# pg_proc.pronargs can be derived from proargtypes.
		if (defined $row->{proargtypes})
		{
			my @proargtypes = split /\s+/, $row->{proargtypes};
			$row->{pronargs} = scalar(@proargtypes);
		}
	}

	# Now fill in defaults, and note any columns that remain undefined.
	foreach my $column (@$schema)
	{
		my $attname = $column->{name};
		my $atttype = $column->{type};

		if (defined $row->{$attname})
		{
			;
		}
		elsif (defined $column->{default})
		{
			$row->{$attname} = $column->{default};
		}
		else
		{
			# Failed to find a value.
			push @missing_fields, $attname;
		}
	}

	# Failure to provide all columns is a hard error.
	if (@missing_fields)
	{
		die sprintf "missing values for field(s) %s in %s.dat line %s\n",
		  join(', ', @missing_fields), $catname, $row->{line_number};
	}
}

# Rename temporary files to final names.
# Call this function with the final file name and the .tmp extension.
#
# If the final file already exists and has identical contents, don't
# overwrite it; this behavior avoids unnecessary recompiles due to
# updating the mod date on unchanged header files.
#
# Note: recommended extension is ".tmp$$", so that parallel make steps
# can't use the same temp files.
sub RenameTempFile
{
	my $final_name = shift;
	my $extension  = shift;
	my $temp_name  = $final_name . $extension;

	if (-f $final_name
		&& compare($temp_name, $final_name) == 0)
	{
		unlink($temp_name) || die "unlink: $temp_name: $!";
	}
	else
	{
		rename($temp_name, $final_name) || die "rename: $temp_name: $!";
	}
	return;
}

# Find a symbol defined in a particular header file and extract the value.
# include_path should be the path to src/include/.
sub FindDefinedSymbol
{
	my ($catalog_header, $include_path, $symbol) = @_;
	my $value;

	# Make sure include path ends in a slash.
	if (substr($include_path, -1) ne '/')
	{
		$include_path .= '/';
	}
	my $file = $include_path . $catalog_header;
	open(my $find_defined_symbol, '<', $file) || die "$file: $!";
	while (<$find_defined_symbol>)
	{
		if (/^#define\s+\Q$symbol\E\s+(\S+)/)
		{
			$value = $1;
			last;
		}
	}
	close $find_defined_symbol;
	return $value if defined $value;
	die "$file: no definition found for $symbol\n";
}

# Similar to FindDefinedSymbol, but looks in the bootstrap metadata.
sub FindDefinedSymbolFromData
{
	my ($data, $symbol) = @_;
	foreach my $row (@{$data})
	{
		if ($row->{oid_symbol} eq $symbol)
		{
			return $row->{oid};
		}
	}
	die "no definition found for $symbol\n";
}

# Extract an array of all the OIDs assigned in the specified catalog headers
# and their associated data files (if any).
# Caution: genbki.pl contains equivalent logic; change it too if you need to
# touch this.
sub FindAllOidsFromHeaders
{
	my @input_files = @_;

	my @oids = ();

	foreach my $header (@input_files)
	{
		$header =~ /(.+)\.h$/
		  or die "Input files need to be header files.\n";
		my $datfile = "$1.dat";

		my $catalog = Catalog::ParseHeader($header);

		# We ignore the pg_class OID and rowtype OID of bootstrap catalogs,
		# as those are expected to appear in the initial data for pg_class
		# and pg_type.  For regular catalogs, include these OIDs.
		if (!$catalog->{bootstrap})
		{
			push @oids, $catalog->{relation_oid}
			  if ($catalog->{relation_oid});
			push @oids, $catalog->{rowtype_oid} if ($catalog->{rowtype_oid});
		}

		# Not all catalogs have a data file.
		if (-e $datfile)
		{
			my $catdata =
			  Catalog::ParseData($datfile, $catalog->{columns}, 0);

			foreach my $row (@$catdata)
			{
				push @oids, $row->{oid} if defined $row->{oid};
			}
		}

		foreach my $toast (@{ $catalog->{toasting} })
		{
			push @oids, $toast->{toast_oid}, $toast->{toast_index_oid};
		}
		foreach my $index (@{ $catalog->{indexing} })
		{
			push @oids, $index->{index_oid};
		}
	}

	return \@oids;
}

1;
