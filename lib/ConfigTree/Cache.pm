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

package ConfigTree::Cache;

use DB_File;
use POSIX;

sub DbRef { shift->_getAndSet('DbRef', @_) };
sub Dbh { shift->_getAndSet('Dbh', @_) };
sub Base { shift->_getAndSet('Base', @_) };
sub Warn { shift->_getAndSet('Warn', @_) };

sub _getAndSet {
    my($self, $field, $value) = @_;
    my($retval) = $self->{$field};
    $self->{$field} = $value if ($#_ >= 2);
    return $retval;
}

sub new {
    my($class) = @_;
    my($self) = {};
    $self->{"LastCompile"} = 0;

    bless $self, $class;
    return $self;
}

sub init {
    my($self) = @_;

    my($file) = $self->{"Base"} . "/config.db";
    my ($dbh);

    my ($useSlurp) = 0;
    my($mtime) = (stat($file))[9];
    if ($self->{"LastCompile"} == $mtime) {
	return $self->Dbh();
    }

    $Common::global::gDbAccess ||= "slurp";
    if (($Common::global::gDbAccess eq "slurp") &&
        ($Common::global::isCollector == 1)) {
            $useSlurp = 1;
    }

    if ($useSlurp) {
        ($dbh) = tie %db2, 'DB_File', $file, O_RDONLY, 0644, $DB_BTREE;
        %db = %db2;
    } else {
        ($dbh) = tie %db, 'DB_File', $file, O_RDONLY, 0644, $DB_BTREE;
    }

    $self->DbRef(\%db);
    $self->Dbh($dbh);

    $self->{"LastCompile"} = $mtime if $dbh;
    return $dbh;
}

sub nodeExists {
    my($self, $node) = @_;
    return defined($self->{"DbRef"}->{'p:' . $node});
}

sub visitLeafs {
    my($self, $parent, $cb, @args) = @_;
    my($dbref) = $self->{"DbRef"};

    my($children) = $dbref->{'c:' . $parent};
    if ($children) {
        my($child);
        foreach $child (split(/,/, $children)) {
            $self->visitLeafs($child, $cb, @args);
        }
    } else {
        if (! $self->isDir($parent)) {
            &{$cb}($parent, @args);
        }
    }

    return;
}

sub configHash {
    my($self, $node, $dict, $name, $exp) = @_;
    my($dbRef) = $self->{"DbRef"};

    # if they ask for a part of the config tree that does not
    # exist, return an error immediately.
    if (! $self->nodeExists($node)) {
        return;
    }

    # walk up from the node in question, finding a path to
    # the root. Build up the list backwards so going thru it forwards
    # is a path from the root to the node of interest.

    my(@path, $curnode);
    $curnode = $node;
    while (length($curnode) > 0) {
        unshift @path, $curnode;
        last unless ($curnode =~ s/\/[^\/]+$//);
    }
    unshift @path, "/";

    # now that we have a path from the root down, compile all the
    # data into a hash to hand back to the caller.

    my($hash) = {};

    # one good special case deserves another. Sigh.
    if ($dict eq 'target') {
        ($name) = ($node =~ /^.*\/(.*)$/);
    }

    # when they give us no name, they are looking for one of the
    # goofy nameless dicts.
    if (! defined($name)) {
        $name = '--merril--';
    }

    my($item);
    foreach $item (@path) {
        my($tags, $tag);

        # try once for --def--
        $tags = $dbRef->{"t:$item:$dict:--default--"};
        $tags = '' unless defined($tags);

        foreach $tag (split(/,/, $tags)) {
            $hash->{$tag} = $dbRef->{"d:$item:$dict:--default--:$tag"};
        }

        # ...and try once for $name
        $tags = $dbRef->{"t:$item:$dict:$name"};
        $tags = '' unless defined($tags);

        foreach $tag (split(/,/, $tags)) {
            $hash->{$tag} = $dbRef->{"d:$item:$dict:$name:$tag"};
        }
    }

    # auto-expand, if the caller asked us to
    if (defined($exp)) {
        if (ref($exp) eq 'HASH') {
            expandHash($hash, $exp, $self->{"Warn"});
        } else {
            # they want us to setup a target hash for them...
            addAutoVariables($node, $hash, $self->{"Base"});
            expandHash($hash, $hash, $self->{"Warn"});
        }
    }

    return $hash;
}

sub addAutoVariables {
    my($name, $target, $base) = @_;

    my($tpath, $tname) = ($name =~ /^(.*)\/(.*)$/);

    $target->{'auto-base'} = $base;
    $target->{'auto-target-path'} = $tpath;
    $target->{'auto-target-name'} = $tname;

    my($root) = $tpath;
    $root =~ s/([^\/]+)/../g;
    $target->{'auto-root'} = $root;

    return;
}

sub getChildren {
    my($self, $name) = @_;

    my($c) = $self->{"DbRef"}->{"c:$name"};
    if (defined($c)) {
        return split(/,/, $c);
    }
    return ();
}

sub isDir {
    my($self, $name) = @_;
    if (defined($self->{"DbRef"}->{"r:$name"})) {
        return 1;
    } else {
        return 0;
    }
}

sub isLeaf {
    my($self, $name) = @_;
    my(@c) = $self->getChildren($name);
    return (($#c+1 == 0) && (! $self->isDir($name)));
}

sub needsRecompile {
    my($self) = @_;

    my($db) = $self->{"DbRef"};
    my($files) = $db->{"F:"};
    if (defined($files)) {
        my($file);
        foreach $file (split(/,/, $files)) {
            my($mtime) = (stat($file))[9];
            if (defined($mtime)) {
                my($mtime2) = $db->{"f:$file"};
                if (defined($mtime2)) {
                    if ($mtime > $mtime2) {
                        return (1,
                             "File $file is newer than the compiled version.");
                    }
                } else {
                    return (1, "Missing file mtime for file $file");
                }
            } else {
                return (1, "Referenced file $file not found.");
            }
        }
        return 0;
    } else {
        return (1, "Could not find file list.");
    }
}

sub expandString {
    # Expand any variables in the datasource definitions for a target.
    my($str, $wrt, $w) = @_;

    # Replace all %variables%
    my($name, $repl);
    while ( $str =~ /%([^\s%]*)%/ ) {
        $name = $1;
        $repl = $wrt->{lc($name)};
        if ( defined $repl ) {
            $str =~ s/%$name%/$repl/;
        } else {
            my($sstr) = $str;
            if (length($sstr) > 20) {
                $sstr = substr($sstr, 0, 17) . "...";
            };
            &{$w}("Found unknown tag '$name' during expansion of '$sstr'.");

            # mark it as not found
            $str =~ s/%$name%/!$name!/;
        }
    }
    return $str;
}

sub evalString {
    # handle any {}'s in the string, which get eval'd
    my($str, $w) = @_;

    # Replace all {expr}'s
    while ( $str =~ /^(.*)\{([^%]*)\}(.*)$/ ) {
        my($before, $expr, $after) = ($1, $2, $3);
        my($repl);
        my(@res) = eval("package Runtime; $expr");
        if ($@) {
            &{$w}("Problem during eval of $expr: $@");
            $repl = "##error##";
        } else {
            $repl = join(", ", @res);
        }
        $str = $before . $repl . $after;
    }

    return $str;
}

sub expandHash {
    my($hash, $wrt, $w) = @_;

    my($k);
    foreach $k (keys(%{$hash})) {
        my $hp = \$hash->{$k};
        if (index($$hp, "%") >= 0) {
            $$hp = expandString($$hp, $wrt, $w);
        }
        if (index($$hp, "{") >= 0) {
            $$hp = evalString($$hp, $w);
        }
    }
}

1;

# Local Variables:
# mode: perl
# indent-tabs-mode: nil
# tab-width: 4
# perl-indent-level: 4
# End:
