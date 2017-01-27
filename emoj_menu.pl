use strict; use warnings;
$INC{'Encode/ConfigLocal.pm'}=1;
require Encode;

# emoj_menu.pl is written by David Britton <davidpbritton@gmail.com>
# and licensed under the under GNU General Public License v3
# or any later version
#
# to read the following docs, you can use "perldoc emoj_menu.pl"

=head1 NAME

emoj_menu - popup menu for the weechat emoj checker (weechat edition)

=head1 USAGE

TBD

=head1 CAVEATS

You need 'emoj' available in your PATH.

=cut

use constant SCRIPT_NAME => 'emoj_menu';
weechat::register(SCRIPT_NAME, 'David Britton <davidpbritton@gmail.com>', '0.1', 'GPL3', 'emoj menu', '', '') || return;
sub SCRIPT_FILE() {
	my $infolistptr = weechat::infolist_get('perl_script', '', SCRIPT_NAME);
	my $filename = weechat::infolist_string($infolistptr, 'filename') if weechat::infolist_next($infolistptr);
	weechat::infolist_free($infolistptr);
	return $filename unless @_;
}

{
package Nlib;
# this is a weechat perl library
use strict; use warnings; no warnings 'redefine';

## i2h -- copy weechat infolist content into perl hash
## $infolist - name of the infolist in weechat
## $ptr - pointer argument (infolist dependend)
## @args - arguments to the infolist (list dependend)
## $fields - string of ref type "fields" if only certain keys are needed (optional)
## returns perl list with perl hashes for each infolist entry
sub i2h {
	my %i2htm = (i => 'integer', s => 'string', p => 'pointer', b => 'buffer', t => 'time');
	local *weechat::infolist_buffer = sub { '(not implemented)' };
	my ($infolist, $ptr, @args) = @_;
	$ptr ||= "";
	my $fields = ref $args[-1] eq 'fields' ? ${ pop @args } : undef;
	my $infptr = weechat::infolist_get($infolist, $ptr, do { local $" = ','; "@args" });
	my @infolist;
	while (weechat::infolist_next($infptr)) {
		my @fields = map {
			my ($t, $v) = split ':', $_, 2;
			bless \$v, $i2htm{$t};
		}
		split ',',
			($fields || weechat::infolist_fields($infptr));
		push @infolist, +{ do {
			my (%list, %local, @local);
			map {
				my $fn = 'weechat::infolist_'.ref $_;
				my $r = do { no strict 'refs'; &$fn($infptr, $$_) };
				if ($$_ =~ /^localvar_name_(\d+)$/) {
					$local[$1] = $r;
					()
				}
				elsif ($$_ =~ /^(localvar)_value_(\d+)$/) {
					$local{$local[$2]} = $r;
					$1 => \%local
				}
				elsif ($$_ =~ /(.*?)((?:_\d+)+)$/) {
					my ($key, $idx) = ($1, $2);
					my @idx = split '_', $idx; shift @idx;
					my $target = \$list{$key};
					for my $x (@idx) {
						my $o = 1;
						if ($key eq 'key' or $key eq 'key_command') {
							$o = 0;
						}
						if ($x-$o < 0) {
							local $" = '|';
							weechat::print('',"list error: $target/$$_/$key/$x/$idx/@idx(@_)");
							$o = 0;
						}
						$target = \$$target->[$x-$o]
					}
					$$target = $r;

					$key => $list{$key}
				}
				else {
					$$_ => $r
				}
			} @fields
		} };
	}
	weechat::infolist_free($infptr);
	!wantarray && @infolist ? \@infolist : @infolist
}

## hdh -- hdata helper
## $_[0] - arg pointer or hdata list name
## $_[1] - hdata name
## $_[2..$#_] - hdata variable name
## $_[-1] - hashref with key/value to update (optional)
## returns value of hdata, and hdata name in list ctx, or number of variables updated
sub hdh {
	if (@_ > 1 && $_[0] !~ /^0x/ && $_[0] !~ /^\d+$/) {
		my $arg = shift;
		unshift @_, weechat::hdata_get_list(weechat::hdata_get($_[0]), $arg);
	}
	while (@_ > 2) {
		my ($arg, $name, $var) = splice @_, 0, 3;
		my $hdata = weechat::hdata_get($name);
		unless (ref $var eq 'HASH') {
			$var =~ s/!(.*)/weechat::hdata_get_string($hdata, $1)/e;
			(my $plain_var = $var) =~ s/^\d+\|//;
			my $type = weechat::hdata_get_var_type_string($hdata, $plain_var);
			if ($type eq 'pointer') {
				my $name = weechat::hdata_get_var_hdata($hdata, $var);
				unshift @_, $name if $name;
			}

			my $fn = "weechat::hdata_$type";
			unshift @_, do { no strict 'refs';
							 &$fn($hdata, $arg, $var) };
		}
		else {
			return weechat::hdata_update($hdata, $arg, $var);
		}
	}
	wantarray ? @_ : $_[0]
}

use Pod::Select qw();
use Pod::Simple::TextContent;

## get_desc_from_pod -- return setting description from pod documentation
## $file - filename with pod
## $setting - name of setting
## returns description as text
sub get_desc_from_pod {
	my $file = shift;
	return unless -s $file;
	my $setting = shift;

	open my $pod_sel, '>', \my $ss;
	Pod::Select::podselect({
	   -output => $pod_sel,
	   -sections => ["SETTINGS/$setting"]}, $file);

	my $pt = new Pod::Simple::TextContent;
	$pt->output_string(\my $ss_f);
	$pt->parse_string_document($ss);

	my ($res) = $ss_f =~ /^\s*\Q$setting\E\s+(.*)\s*/;
	$res
}

## get_settings_from_pod -- retrieve all settings in settings section of pod
## $file - file with pod
## returns list of all settings
sub get_settings_from_pod {
	my $file = shift;
	return unless -s $file;

	open my $pod_sel, '>', \my $ss;
	Pod::Select::podselect({
	   -output => $pod_sel,
	   -sections => ["SETTINGS//!.+"]}, $file);

	$ss =~ /^=head2\s+(.*)\s*$/mg
}

## mangle_man_for_wee -- turn man output into weechat codes
## @_ - list of grotty lines that should be turned into weechat attributes
## returns modified lines and modifies lines in-place
sub mangle_man_for_wee {
	for (@_) {
		s/_\x08(.)/weechat::color('underline').$1.weechat::color('-underline')/ge;
		s/(.)\x08\1/weechat::color('bold').$1.weechat::color('-bold')/ge;
	}
	wantarray ? @_ : $_[0]
}

## read_manpage -- read a man page in weechat window
## $file - file with pod
## $name - buffer name
sub read_manpage {
	my $caller_package = (caller)[0];
	my $file = shift;
	my $name = shift;

	if (my $obuf = weechat::buffer_search('perl', "man $name")) {
		eval qq{
			package $caller_package;
			weechat::buffer_close(\$obuf);
		};
	}

	my @wee_keys = Nlib::i2h('key');
	my @keys;

	my $winptr = weechat::current_window();
	my ($wininfo) = Nlib::i2h('window', $winptr);
	my $buf = weechat::buffer_new("man $name", '', '', '', '');
	return weechat::WEECHAT_RC_OK unless $buf;

	my $width = $wininfo->{chat_width};
	--$width if $wininfo->{chat_width} < $wininfo->{width} || ($wininfo->{width_pct} < 100 && (grep { $_->{y} == $wininfo->{y} } Nlib::i2h('window'))[-1]{x} > $wininfo->{x});
	$width -= 2; # when prefix is shown

	weechat::buffer_set($buf, 'time_for_each_line', 0);
	eval qq{
		package $caller_package;
		weechat::buffer_set(\$buf, 'display', 'auto');
	};
	die $@ if $@;

	@keys = map { $_->{key} }
		grep { $_->{command} eq '/input history_previous' ||
			   $_->{command} eq '/input history_global_previous' } @wee_keys;
	@keys = 'meta2-A' unless @keys;
	weechat::buffer_set($buf, "key_bind_$_", '/window scroll -1') for @keys;

	@keys = map { $_->{key} }
		grep { $_->{command} eq '/input history_next' ||
			   $_->{command} eq '/input history_global_next' } @wee_keys;
	@keys = 'meta2-B' unless @keys;
	weechat::buffer_set($buf, "key_bind_$_", '/window scroll +1') for @keys;

	weechat::buffer_set($buf, 'key_bind_ ', '/window page_down');

	@keys = map { $_->{key} }
		grep { $_->{command} eq '/input delete_previous_char' } @wee_keys;
	@keys = ('ctrl-?', 'ctrl-H') unless @keys;
	weechat::buffer_set($buf, "key_bind_$_", '/window page_up') for @keys;

	weechat::buffer_set($buf, 'key_bind_g', '/window scroll_top');
	weechat::buffer_set($buf, 'key_bind_G', '/window scroll_bottom');

	weechat::buffer_set($buf, 'key_bind_q', '/buffer close');

	weechat::print($buf, " \t".mangle_man_for_wee($_)) # weird bug with \t\t showing nothing?
			for `pod2man \Q$file\E 2>/dev/null | GROFF_NO_SGR=1 nroff -mandoc -rLL=${width}n -rLT=${width}n -Tutf8 2>/dev/null`;
	weechat::command($buf, '/window scroll_top');

	unless (hdh($buf, 'buffer', 'lines', 'lines_count') > 0) {
		weechat::print($buf, weechat::prefix('error').$_)
				for "Unfortunately, your @{[weechat::color('underline')]}nroff".
					"@{[weechat::color('-underline')]} command did not produce".
					" any output.",
					"Working pod2man and nroff commands are required for the ".
					"help viewer to work.",
					"In the meantime, please use the command ", '',
					"\tperldoc $file", '',
					"on your shell instead in order to read the manual.",
					"Thank you and sorry for the inconvenience."
	}
}

1
}


my %emoj_menu;
init_emoj_menu();
weechat::hook_command(
    SCRIPT_NAME,
    'open the emoj correction menu',
    '',
    "use @{[weechat::color('bold')]}/@{[SCRIPT_NAME]} help@{[weechat::color('-bold')]} to read the manual",
    '',
    SCRIPT_NAME,
    '');
weechat::hook_info_hashtable(
    SCRIPT_NAME,
    'emoj menu content',
    '',
    'list of n.command and n.name pairs for insertion into menu',
    SCRIPT_NAME,
    '');

## emoj_menu -- show the emoj menu
## () - command_run or command handler
## $_[1] - buffer or infohash name
## $_[2] - command or arg
sub emoj_menu {
    weechat::print('', "DEBUG: emoj_menu(".$_[1].", ".$_[2].")");
    my $input = weechat::buffer_get_string($_[1], 'input');
	my $input_pos = weechat::buffer_get_integer($_[1], 'input_pos');
	if (ref $_[2]) {
		return \%emoj_menu;
	}
	if ($_[2] =~ /^\s*help\s*$/i) {
		Nlib::read_manpage(SCRIPT_FILE, SCRIPT_NAME);
		return weechat::WEECHAT_RC_OK
	}

	my $append = $1 if $_[2] =~ /^append (.+)/;
    if ($append) {
        # TODO: get smarter about input, allow insertion.
        $input .= $append;
        $input_pos++;
        weechat::buffer_set($_[1], 'input', $input);
		weechat::buffer_set($_[1], 'input_pos', $input_pos);
		return weechat::WEECHAT_RC_OK
    }

    chomp(my $result = `emoj $input`);
    my @choices = split(/\s+/, $result);
    my %new_menu;
    my $i = 0;
    for my $choice (@choices) {
        $new_menu{"$i.command"} = "/@{[SCRIPT_NAME]} append $choice";
        $new_menu{"$i.name"} = "&$i $choice";
        $i++;
    }
    %emoj_menu = %new_menu;
    weechat::command($_[1], "/menu emoj");

	return weechat::WEECHAT_RC_OK
}

sub init_emoj_menu {
	weechat::command('', '/mute /set menu.var.emoj.0.command %#emoj_menu% % ');
	weechat::WEECHAT_RC_OK
}
