# Cricket: a configuration, polling and data display wrapper for RRD files
#
#    Copyright (C) 1998 Jeff R. Allen and WebTV Networks, Inc.
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

package ConfigTree::Node;

use strict;
use Text::ParseWords;
use Date::Parse;
use FileHandle;
use DB_File;
use POSIX;

my($gDebug) = 0;

# tokens which need no name
my(%gSkipName) = ( 'oid' => 1, 'rra' => 1, 'html' => 1,
					'color' => 1);
my(%gTextTags) = ( 'html' => 1 );

sub Name { shift->_getAndSet('Name', @_) };
sub Base { shift->_getAndSet('Base', @_) };
sub Next { shift->_getAndSet('Next', @_) };
sub Prev { shift->_getAndSet('Prev', @_) };
sub File { shift->_getAndSet('File', @_) };
sub NodeCfg { shift->_getAndSet('NodeCfg', @_) };
sub Parent { shift->_getAndSet('Parent', @_) };
sub Files { shift->_getAndSet('Files', @_) };
sub Preload { shift->_getAndSet('Preload', @_) };
sub Done { shift->_getAndSet('Done', @_) };
sub Dir { shift->_getAndSet('Dir', @_) };

# logging callbacks
sub info { shift->_getAndSet('info', @_) };
sub warn { shift->_getAndSet('warn', @_) };
sub debug { shift->_getAndSet('debug', @_) };

sub _getAndSet {
	my($self, $field, $value) = @_;
	my($retval) = $self->{$field};
	$self->{$field} = $value if ($#_ >= 2);
	return $retval;
}

sub new {
	my($class, $tmpl) = @_;
	my($self) = {};

	bless($self, $class);

	# init the local config to an empty hash, so it's ready to fill
	# later (in parseLines()).
	$self->NodeCfg({});

	# if we have a template object, copy some interesting things
	# from it
	if (defined($tmpl)) {
		$self->info($tmpl->info());
		$self->warn($tmpl->warn());
		$self->debug($tmpl->debug());
		$self->Base($tmpl->Base());
		$self->Files($tmpl->Files());

		# copy the preload stuff in, if necessary
		if ($tmpl->Preload()) {
			$self->Debug("Got preload...");
			my($fm) = $tmpl->Preload()->NodeCfg();
			my($to) = $self->NodeCfg();
			my($dict, $name, $tag, $v1, $v2, $v3);
			while (($dict, $v1) = each(%{$fm})) {
				while (($name, $v2) = each(%{$v1})) {
					while (($tag, $v3) = each(%{$v2})) {
						$to->{$dict}->{$name}->{$tag} = $v3;
						$self->Debug("$dict:$name:$tag = $v3");
					}
				}
			}
		}
	}

	return $self;
}

sub init {
	my($self, $name) = @_;

	if (! defined($name)) {
		# this is the first call to init().
		$name = '/';
		$self->Files({});
	}

	$self->Debug("Setting name to $name");
	$self->Name($name);

	my($dir) = $self->Base() . $self->Name();
	$dir =~ s/\/$//;

	my($item, @files, @dirs, $def);
	foreach $item (<$dir/*>) {
		if ($item =~ /\/Defaults$/ && -f $item) {
			$def = $item;
		} elsif (-f $item) {
			push @files, $item unless $self->skipFile($item);
		} elsif (-d $item) {
			push @dirs, $item unless $self->skipFile($item);
		} else {
			$self->Warn("Unknown object type for $item.");
		}
	}

	if ($def) {
		$self->_readFile($def);
	}

	foreach $item (@files) {
		$self->_readFile($item, 1);
	}
	
	foreach $item (@dirs) {
		my($path, $dirName) = ($item =~ /^(.*)\/(.*)$/);

		my($new) = new ConfigTree::Node $self;
		$new->Dir(1);

		my($newName) = $self->Name() . "/" . $dirName;
		$newName =~ s#^\/\/#\/#;
		$new->init($newName);

		$self->addChild($new);
	}
}

sub dump {
	my($self) = @_;

	$self->doTree(
		sub {
			$self->Info(("  " x $_[2]) . "Name: " . $_[0]->Name())
		}
		);

	return;
}

sub compile {
	my($self, $base) = @_;

	# default to the config tree's base
	$base = $self->Base() unless ($base);

    my($file) = "$base/config.db.new";
    my($finalFile) = "$base/config.db";
 
    # we are being asked to do a complete rebuild, so start
    # from scratch
    unlink($file);

    my(%db);
    my($dbh) = tie %db, 'DB_File', $file, O_CREAT|O_RDWR, 0644, $DB_HASH;

	my($ct) = $self->compileTree(\%db);

	# put the entire set of files into the compiled form, so that
	# we can compare the mtimes later and recompile if necessary
	my($f);
	my($filesRef) = $self->Files();
	my(@f) = keys(%{$filesRef});
	foreach $f (@f) {
		$db{"f:$f"} = $filesRef->{$f};
	}
	$db{"F:"} = join(',', @f);

	undef $dbh;
    untie %db;

    rename($file, $finalFile);

	return ($ct, $#f+1);
}

sub compileTree {
	my($self, $dbref) = @_;
	my($ct) = 0;

    $self->compileNode($dbref);
    $ct++;
 
    my($child);
    foreach $child ($self->getChildren()) {
        $ct += $child->compileTree($dbref);
	}

	return $ct;
}

sub compileNode {
	my($self, $dbRef) = @_;

	# put the data from the config hash into the db, along with
	# enough data to let us avoid seq-ing over it. We don't want to
	# use seq, since it's Btree-specific, and we don't want to
	# stick people with that. (They should be able to use (ugh) dbm if
	# they need to.)

	my($node) = $self->Name();
	my($cfg) = $self->NodeCfg();

	my($dict, $name, $tag, $v, @dicts, @names, @tags);
	@dicts = ();
	foreach $dict (keys(%{$cfg})) {
		@names = ();
		foreach $name (keys(%{$cfg->{$dict}})) {
			@tags = ();
			foreach $tag (keys(%{$cfg->{$dict}->{$name}})) {
				$dbRef->{"d:$node:$dict:$name:$tag"} =
					$cfg->{$dict}->{$name}->{$tag};
				push @tags, $tag;
			}
			$dbRef->{"t:$node:$dict:$name"} = join(',', @tags);
			push @names, $name;
		}
		$dbRef->{"n:$node:$dict"} = join(',', @names);
		push @dicts, $dict;
	}
	$dbRef->{"D:$node"} = join(',', @dicts);

	# put a comma-separated list of the relative names of the children
	# into a "c:" key in the db.
	my($child, @children);
	foreach $child ($self->getChildren()) {
		push @children, $child->Name();
	}
	$dbRef->{'c:' . $node } = join(',', @children);

	# tuck the parent into a "p:" key.
	if ($self->Parent()) {
		$dbRef->{'p:' . $node } = $self->Parent()->Name();
	} else {
		$dbRef->{'p:' . $node } = '';
	}

	if ($self->Dir()) {
		$dbRef->{'r:' . $node } = 1;
	}

	# Just to recap:
	#	d is for data
	#	t is for tags
	#	n is for names
	#	D is for dicts
	#	c if for a list of children
	#	p is for the name of the parent
	#	r:$name is 1 when this node is a directory (lets us ignore empty
	#		directories later)
	#	f:file => mtime
	#	F: => comma separated list of files
}

sub processTree {
	my($self) = @_;

    $self->processNode();
 
    my($child);
    foreach $child ($self->getChildren()) {
		if ( $child ne 'CVS' ) {
        	$child->processTree();
		}
	}
}

# Here we do any post-processing of the config that we desire.

# Right now, we just parse the event dates into times,
# so that the grapher does not have to.

sub processNode {
	my($self) = @_;

	my($name) = $self->Name();
	my($cfg) = $self->NodeCfg();

	my($evRef) = $cfg->{'event'};
	if ($evRef) {
		my($evName);
		foreach $evName (keys(%{$evRef})) {
			my($evDate) = $evRef->{$evName}->{'date'};
			if ($evDate && !defined($evRef->{$evName}->{'time'})) {
				my($t) = str2time($evDate);
				if (! defined($t)) {
					$self->Warn("Could not parse date $evDate ".
								"for event $evName");
				} else {
					$evRef->{$evName}->{'time'} = $t;
					$self->Debug("date string $evDate for $evName becomes time $t");
				}
			}
		}
	}
}

sub addChild {
	my($self, @children) = @_;

	my($child);
	foreach $child (@children) {
		$child->Parent($self);
	}

	push @{$self->{'Children'}}, @children;
	return;
}

sub getChildren {
	my($self) = @_;
	if ($self->{'Children'}) {
		return @{$self->{'Children'}};
	} else {
		return ();
	}
}

sub _readFile {
	my($self, $file, $leaf) = @_;
    my($buffer);
 
    # $self->Debug("Processing file: $file");
	$self->File($file);

	my($fh) = new FileHandle; 
	if (! $fh->open("<$file")) {
		$self->Warn("Cannot parse $file: $!");
	} else {
		my($line);
		while (defined($line = <$fh>)) {
			chomp($line);
 
			# handle comments and blank lines
			$line =~ s/^\s*#.*$//;
			next if ($line =~ /^\s*$/);
 
			if ($line !~ /^\s/) {
				# this is an initial line
				$self->parseLines($buffer, $leaf) if $buffer;
				$buffer = $line;
			} else {
				# this is a continuation line
				$buffer .= "\n";
				$buffer .= $line;
			}
		}
	}
	$self->parseLines($buffer, $leaf) if $buffer;

	my($mtime) = (stat($fh))[9];
	if (! defined($mtime)) {
		$self->Warn("Could not get mtime for file $file.");
	} else {
		($self->Files())->{$file} = $mtime;
	}

	$fh->close();
}

sub parseLines {
	my($self, $lines, $leaf) = @_;
	my(@words);
	my($at) = "at (or before) " . $self->File() . " line ${.}.";

	$lines =~ s/\s*$//;
    eval {
        local $SIG{'__DIE__'};
        @words = quotewords('[\s=]+', 0, $lines);
    };

    # make unmatched quote errors that quotewords throws
    # easier to find
    if ($@ =~ /Unmatched/) {
        $@ =~ s/ at .*$//;
        $@ =~ s/\n//;
		$self->Warn("$@ $at");
		return;
    }

    my($token) = lc(shift @words);
    if (! defined($token)) {
		$self->Warn("Missing token $at");
		return;
    }

	my($isText) = $gTextTags{$token};

    my($name);
	if ($isText || $gSkipName{$token}) {
		# it was the CD I was listening to at the time... sue me.
		$name = '--merril--';
	} else {
		$name = lc(shift @words);
    	if (! defined($name)) {
			$self->Warn("Missing $token name $at");
			return;
    	}
	}

	# forge a dictionary if this is a text tag, so that the
	# coming code can handle it without changes.
	if ($isText) {
		my($junk, $key, $text) = split(/\s+/, $lines, 3);
		@words = ($key, $text);
	}

	# make certain there's a valid dict left to parse.
    if (!$isText && ($#words+1) % 2) {
		$self->Warn("Missing equals sign $at");
		return;
    }

	my($node);
	if ($token eq 'target') {
		if ($name eq '--default--') {
			if ($self->Done()) {
				if (! $self->Preload()) {
					$self->Debug("Making a preload node.");
					$self->Preload(new ConfigTree::Node);
				}
				$node = $self->Preload();
				$self->Debug("Using a preload node.");
			} else {
				$node = $self;
			}
		} else {
			$node = new ConfigTree::Node $self;
			$node->Name($self->Name() . "/$name");
			$self->addChild($node);
		}
	} else {
		$node = $self;
	}

    # all this mess is to get a reference to a hash where
    # the parser will be allowed to scribble.
    my($cfgRef) = $node->NodeCfg();
    if (! defined($cfgRef->{$token})) {
        $cfgRef = ($cfgRef->{$token} = {});
    } else {
        $cfgRef = $cfgRef->{$token};
    }

    # if the key does not exist already... create an empty
    # key for it. This is so that in the unlikely case there
    # are no defaults and no attributes, a hash will still
    # get created as a placeholder, to be correct.

    if (! defined($cfgRef->{$name})) {
        $cfgRef->{$name} = {};
    }

    my($k, $v);

    # now, take the stuff from the @words array and add to the
    # hash under construction. Unless the value is precisely
    # "undef", then we delete that key.

    while ($#words != -1) {
        $k = lc(shift @words);
        $v = shift @words;

        if ($v eq 'undef') {
            delete($cfgRef->{$name}->{$k});
            next;
        }

        $cfgRef->{$name}->{$k} = $v;
    }

	$self->Done(1);

    return 1;
}

sub getNode {
	my($self, $nodeName) = @_;

	if ($nodeName eq $self->Name()) {
		return $self;
	} else {
		my($child);
		foreach $child ($self->getChildren()) {
			my($res) = $child->getNode($nodeName);
			return $res if (defined($res));
		}
		return;
	}
}

sub Debug {
    my($self, $msg) = @_;
	$msg = "[" . ($self->Name() ? $self->Name() : "?") . "] $msg";

    if (defined($self->{'debug'})) {
        &{$self->{'debug'}}($msg);
    } else {
        CORE::warn("DEBUG: " . $msg . "\n") if ($gDebug);
    }
}
 
sub Info {
    my($self, $msg) = @_;
    if (defined($self->{'info'})) {
        &{$self->{'info'}}($msg);
    } else {
        CORE::warn($msg . "\n");
    }
}
 
sub Warn {
    my($self, $msg) = @_;
    if (defined($self->{'warn'})) {
        &{$self->{'warn'}}($msg);
    } else {
        CORE::warn("Warning: " . $msg . "\n");
    }
}

sub doTree {
	my($self, $cb, $state, $level) = @_;

	$level = 0 unless(defined($level));

	&{$cb}($self, $state, $level);

	my($child);
	foreach $child ($self->getChildren()) {
		$child->doTree($cb, $state, $level+1);
	}
}

sub isLeaf {
	my($self) = @_;
	return (!defined($self->{'Children'}));
}

sub break {
	print "Splero!\n"
};

sub skipFile {
    my($self, $file) = @_;
    my($res) = 0;
 
    $res = 1 if ($file =~ /\/#.*#$/);
    $res = 1 if ($file =~ /\/README$/);
    $res = 1 if ($file =~ /\/.bak$/);
    $res = 1 if ($file =~ /\/RCS$/);
    $res = 1 if ($file =~ /,v$/);
    $res = 1 if ($file =~ /~$/);
    $res = 1 if ($file =~ /\/config.db$/);
    $res = 1 if ($file =~ /\/config.db.new$/);
    $res = 1 if ($file =~ /\/CVS$/); 
 
    return $res;
}

1;
