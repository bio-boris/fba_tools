package Bio::KBase::utilities;
use strict;
use warnings;
use Carp qw(cluck);
use Config::Simple;
use DateTime;

our $reaction_hash;
our $compound_hash;
our $kegg_hash;
our $config = undef;
our $ctx = undef;
our $timestamp = undef;
our $debugfile = undef;
our $reportmessage = undef;
our $reporthtml = undef;
our $reportfiles = [];
our $reporthtmlfiles = [];
our $processid = undef;
our $loghandler;
our $starttime = undef;
our $arguments = undef;
our $gapfilltable = undef;

sub kegg_hash {
	if (!defined($reaction_hash)) {
		my $pathways = Bio::KBase::ObjectAPI::utilities::LOADFILE(Bio::KBase::utilities::conf("ModelSEED","kegg_pathways"));
		for (my $i=1; $i < @{$pathways}; $i++) {
			my $array = [split(/\t/,$pathways->[$i])];
			$array->[1] =~ s/map/rn/;
			$kegg_hash->{$array->[1]} = $array->[2];
		}
	}
	return $kegg_hash;
};

sub reaction_hash {
	if (!defined($reaction_hash)) {
		my $rxndata = Bio::KBase::ObjectAPI::utilities::FROMJSON(join("\n",@{Bio::KBase::ObjectAPI::utilities::LOADFILE(Bio::KBase::utilities::conf("ModelSEED","reactions_json"))}));
		for (my $i=0; $i < @{$rxndata}; $i++) {
			$reaction_hash->{$rxndata->[$i]->{id}} = $rxndata->[$i];
		}
	}
	return $reaction_hash;
};

sub metabolite_hash {
	my ($id_hash,$name_hash,$structure_hash,$formula_hash,$priority,$cmp) = @_;
	my $cpdhash = Bio::KBase::utilities::compound_hash();
	foreach my $cpdid (keys(%{$cpdhash})) {
		my $data = $cpdhash->{$cpdid};
		if ($cpdid =~ m/(cpd\d+)/) {
			$id_hash->{$1}->{$cpdid."_".$cmp} = $priority;
		}
		if (defined($cpdhash->{$cpdid}->{inchikey})) {
			$structure_hash->{$cpdhash->{$cpdid}->{inchikey}}->{$cpdid."_".$cmp} = $priority;
		}
		if (defined($cpdhash->{$cpdid}->{smiles})) {
			$structure_hash->{$cpdhash->{$cpdid}->{smiles}}->{$cpdid."_".$cmp} = $priority;
		}
		if (defined($cpdhash->{$cpdid}->{formula})) {
			$formula_hash->{$cpdhash->{$cpdid}->{formula}}->{$cpdid."_".$cmp} = $priority;
		}
		if (defined($cpdhash->{$cpdid}->{name})) {
			$name_hash->{Bio::KBase::utilities::nameToSearchname($cpdhash->{$cpdid}->{name})}->{$cpdid."_".$cmp} = $priority;
		}
		if (defined($cpdhash->{$cpdid}->{abbreviation})) {
			$name_hash->{$cpdhash->{$cpdid}->{abbreviation}}->{$cpdid."_".$cmp} = $priority;
		}
		if (defined($cpdhash->{$cpdid}->{names})) {
			foreach my $name (@{$cpdhash->{$cpdid}->{names}}) {
				$name_hash->{$name}->{$cpdid."_".$cmp} = $priority;
			}
		}
	}
}

sub find_matching_metabolite {
	my ($peak_hash,$search_hash,$id,$query) = @_;
	my $matches = 0;
	if (!defined($peak_hash->{$id})) {
		my $querylist = [split(/;/,$query)];
		for (my $j=0; $j < @{$querylist}; $j++) {
			#for (my $i=1; $i < 10; $i++) {
				#if (!defined($peak_hash->{$id}) && defined($search_hash->{$querylist->[$j]})) {
					foreach my $cpdid (keys(%{$search_hash->{$querylist->[$j]}})) {
						#if ($search_hash->{$querylist->[$j]}->{$cpdid} == $i) {
							$matches++;
							$peak_hash->{$id}->{$cpdid} = $search_hash->{$querylist->[$j]};
						#}
					}
				#}
			#}
		}
	}
	return $matches;
}

sub compound_hash {
	if (!defined($compound_hash)) {
		my $cpddata = Bio::KBase::ObjectAPI::utilities::FROMJSON(join("\n",@{Bio::KBase::ObjectAPI::utilities::LOADFILE(Bio::KBase::utilities::conf("ModelSEED","compounds_json"))}));
		for (my $i=0; $i < @{$cpddata}; $i++) {
			$compound_hash->{$cpddata->[$i]->{id}} = $cpddata->[$i];
			if (defined($cpddata->[$i]->{formula}) && defined($cpddata->[$i]->{charge})) {
				$compound_hash->{$cpddata->[$i]->{id}}->{neutral_formula} = Bio::KBase::utilities::compute_neutral_formula($cpddata->[$i]->{formula},$cpddata->[$i]->{charge},$cpddata->[$i]->{id});
			}
		}
	}
	return $compound_hash;
}

sub compute_neutral_formula {
	my ($formula,$charge,$id) = @_;
	my $diff = 0-$charge;
	if ($id eq "cpd00006" || $id eq "cpd00003") {
		$diff++;
	}
	if ($diff == 0) {
		return $formula;
	}
	if ($formula =~ m/H(\d+)/) {
		my $count = $1;
		$count += $diff;
		$formula =~ s/H(\d+)/H$count/;
	} elsif ($formula =~ m/.H$/) {
		if ($diff < 0) {
			$formula =~ s/H$//;
		} else {
			$diff++;
			$formula .= $diff;
		}
	} elsif ($formula =~ m/H[A-Z]/) {
		if ($diff < 0) {
			$formula =~ s/H([A-Z])/$1/;
		} else {
			$diff++;
			$formula =~ s/H([A-Z])/H$diff$1/;
		}
	}
	return $formula;
}

sub style {
	return "	<style>
	.reporttbl {
		border:1px solid #C0C0C0;
		border-collapse:collapse;
		padding:5px;
	}
	.reporttbl th {
		border:1px solid #C0C0C0;
		padding:5px;
		background:#F0F0F0;
	}
	.reporttbl td {
		border:1px solid #C0C0C0;
		text-align:left;
		padding:5px;
	}
	</style>";
}


sub to_json {
    my ($ref,$prettyprint) = @_;
    my $JSON = JSON->new->utf8(1);
    $JSON->allow_blessed([]);
    if (defined($prettyprint) && $prettyprint == 1) {
		$JSON->pretty(1);
    }
    return $JSON->encode($ref);
}

sub arguments {
	my ($input) = @_;
	if (defined($input)) {
		$arguments = $input;
	}
	return $arguments;
}

sub start_time {
	my ($reset) = @_;
	if (!defined($starttime) || (defined($reset) && $reset == 1)) {
		$starttime = time();
	}
	return $starttime;
}

sub start_time_stamp {
	return DateTime->from_epoch( epoch => Bio::KBase::utilities::start_time() )->datetime();
}

sub elapsedtime {
	return time()-Bio::KBase::utilities::start_time();
}

sub set_handler {
	my ($input_handler) = @_;
	$loghandler = $input_handler;
}

sub processid {
	my ($input) = @_;
	if (defined($input)) {
		$processid = $input;
	}
	if (!defined($processid)) {
    	$processid = Data::UUID->new()->create_str();
    }
    return $processid;
}

sub log {
	my ($msg,$tag) = @_;
	$loghandler->util_log($msg,$tag,Bio::KBase::utilities::processid());
}

sub gapfilling_html_table {
	my ($args) = @_;
	$args = Bio::KBase::utilities::args($args,[],{
		message => undef,
		append => 1,
	});
	if (defined($args->{message})) {
		if ($args->{append} == 0 || !defined($gapfilltable)) {
			$gapfilltable = "";
		}
		$gapfilltable .= $args->{message};
	}
	return $gapfilltable;
};

sub print_report_message {
	my ($args) = @_;
	$args = Bio::KBase::utilities::args($args,["message"],{
		append => 1,
		html => 0
	});
	if ($args->{html} == 1) {
		if ($args->{append} == 1) {
			if (!defined($reporthtml)) {
				$reporthtml = "";
			}
			$reporthtml .= $args->{message};
		} else {
			$reporthtml = $args->{message};
		}
	} else {
		if ($args->{append} == 1) {
			if (!defined($reportmessage)) {
				$reportmessage = "";
			}
			$reportmessage .= $args->{message};
		} else {
			$reportmessage = $args->{message};
		}
	}
}

sub report_message {
	return $reportmessage;
}

sub report_html {
	return $reporthtml;
}

sub add_report_file {
	my ($args) = @_;
	$args = Bio::KBase::utilities::args($args,["path","name","description"],{
		html => 0
	});
	if ($args->{html} == 1) {
		push(@{$reporthtmlfiles},{
			path => $args->{path},
			name => $args->{name},
			description => $args->{description},
		});
	} else {
		push(@{$reportfiles},{
			path => $args->{path},
			name => $args->{name},
			description => $args->{description},
		});
	}
}

sub report_files {
	return $reportfiles;
}

sub report_html_files {
	return $reporthtmlfiles;
}

sub config_hash {
	return $config;
}

#read_config: an all purpose general method for reading in service configurations and setting mandatory/optional values
sub read_config {
	my ($args) = @_;
	$args = Bio::KBase::utilities::args($args,[],{
		filename => $ENV{KB_DEPLOYMENT_CONFIG},
		service => $ENV{KB_SERVICE_NAME},
		mandatory => [],
		optional => {}
	});
	if (!defined($args->{service})) {
		Bio::KBase::utilities::error("No service specified!");
	}
	if (!defined($args->{filename})) {
		Bio::KBase::utilities::error("No config file specified!");
	}
	if (!-e $args->{filename}) {
		Bio::KBase::utilities::error("Specified config file ".$args->{filename}." doesn't exist!");
	}
	my $c = Config::Simple->new();
	$c->read($args->{filename});
	my $hash = $c->vars();
	foreach my $key (keys(%{$hash})) {
		my $array = [split(/\./,$key)];
		$config->{$array->[0]}->{$array->[1]} = $hash->{$key};
	}
	$config->{$args->{service}} = Bio::KBase::utilities::args($config->{$args->{service}},$args->{mandatory},$args->{optional});
	$config->{UtilConfig} = Bio::KBase::utilities::args($config->{UtilConfig},[],{
		fulltrace => 0,
		reportimpl => 0,
		call_back_url =>  $ENV{ SDK_CALLBACK_URL },
		token => undef
	});
	#print "Loading config file:".$args->{filename}.":\n".Data::Dumper->Dump([$config])."\n";
	return $config;
}

sub buildref {
	my $id = shift;
	my $ws = shift;
	#Check if the ID is a KBase workspace ID with a version
	if ($id =~ m/^([^\/]+)\/([^\/]+)\/\d+$/) {
		return $id;
	#Check if the ID contains a "/" which indicates that it is a full ref
	} elsif ($id =~ m/\//) {
		return $id;
	}
	#Removing any "/" that may appear at the end of the ws
	$ws =~ s/\/$//;
	return $ws."/".$id;
}

sub parse_input_table {
	my $filename = shift;
	my $columns = shift;#[name,required?(0/1),default,delimiter]
	if (!-e $filename) {
		print "Could not find input file:".$filename."!\n";
		exit();
	}
	if($filename !~ /\.([ct]sv|txt)$/){
    	die("$filename does not have correct suffix (.txt or .csv or .tsv)");
	}
	open(my $fh, "<", $filename) || return;
	my $headingline = <$fh>;
	$headingline =~ tr/\r\n//d;#This line removes line endings from nix and windows files
	my $delim = undef;
	if ($headingline =~ m/\t/) {
		$delim = "\\t";
	} elsif ($headingline =~ m/,/) {
		$delim = ",";
	}
	if (!defined($delim)) {
		die("$filename either does not use commas or tabs as a separator!");
	}
	my $headings = [split(/$delim/,$headingline)];
	my $data = [];
	while (my $line = <$fh>) {
		$line =~ tr/\r\n//d;#This line removes line endings from nix and windows files
		push(@{$data},[split(/$delim/,$line)]);
	}
	close($fh);
	my $headingColums;
	for (my $i=0;$i < @{$headings}; $i++) {
		$headingColums->{$headings->[$i]} = $i;
	}
	my $error = 0;
	for (my $j=0;$j < @{$columns}; $j++) {
		if (!defined($headingColums->{$columns->[$j]->[0]}) && defined($columns->[$j]->[1]) && $columns->[$j]->[1] == 1) {
			$error = 1;
			print "Model file missing required column '".$columns->[$j]->[0]."'!\n";
		}
	}
	if ($error == 1) {
		exit();
	}
	my $objects = [];
	foreach my $item (@{$data}) {
		my $object = [];
		for (my $j=0;$j < @{$columns}; $j++) {
			$object->[$j] = undef;
			if (defined($columns->[$j]->[2])) {
				$object->[$j] = $columns->[$j]->[2];
			}
			if (defined($headingColums->{$columns->[$j]->[0]}) && defined($item->[$headingColums->{$columns->[$j]->[0]}])) {
				$object->[$j] = $item->[$headingColums->{$columns->[$j]->[0]}];
			}
			if (defined($columns->[$j]->[3])) {
				if (defined($object->[$j]) && length($object->[$j]) > 0) {
					my $d = $columns->[$j]->[3];
					$object->[$j] = [split(/$d/,$object->[$j])];
				} else {
					$object->[$j] = [];
				}
			}
		}
		push(@{$objects},$object);
	}
	return $objects;
}

#args: a function for validating argument hashes that checks for mandatory keys and sets default values on optional keys
sub args {
	my ($args,$mandatoryArguments,$optionalArguments,$substitutions) = @_;
	if (!defined($args)) {
	    $args = {};
	}
	if (ref($args) ne "HASH") {
		Bio::KBase::utilities::error("Arguments not hash");	
	}
	if (defined($substitutions) && ref($substitutions) eq "HASH") {
		foreach my $original (keys(%{$substitutions})) {
			$args->{$original} = $args->{$substitutions->{$original}};
		}
	}
	if (defined($mandatoryArguments)) {
		my $mandatorylist;
		for (my $i=0; $i < @{$mandatoryArguments}; $i++) {
			if (!defined($args->{$mandatoryArguments->[$i]})) {
				push(@{$mandatorylist},$mandatoryArguments->[$i]);
			}
		}
		if (defined($mandatorylist)) {
			Bio::KBase::utilities::error("Mandatory arguments missing ".join("; ",@{$mandatorylist}));
		}
	}
	if (defined($optionalArguments)) {
		foreach my $argument (keys(%{$optionalArguments})) {
			if (!defined($args->{$argument})) {
				$args->{$argument} = $optionalArguments->{$argument};
			}
		}	
	}
	return $args;
}

#utilconf: returns values for configurations specifically relating to these utility functions
sub utilconf {
	my ($var) = @_;
	return Bio::KBase::utilities::conf("UtilConfig",$var);
}

#setconf: sets the value of a specific config parameter
sub setconf {
	my ($serv,$var,$value) = @_;
	if (!defined($config)) {
		Bio::KBase::utilities::read_config();
	}
	$config->{$serv}->{$var} = $value;
}

#conf: returns values for all service configurations
sub conf {
	my ($serv,$var) = @_;
	if (!defined($config)) {
		Bio::KBase::utilities::read_config();
	}
	return $config->{$serv}->{$var};
}

#error: prints an error message
sub error {	
	my ($message) = @_;
    if (defined($config) && Bio::KBase::utilities::utilconf("fulltrace") == 1) {
		Carp::confess($message);
    } else {
    	die $message;
    }
}

sub debug {
	my ($message) = @_;
	if (!defined($debugfile)) {
		open ( $debugfile, ">", Bio::KBase::utilities::utilconf("debugfile"));
	}
	print $debugfile $message;
}

sub close_debug {
	if (defined($debugfile)) {
		close($debugfile);
		$debugfile = undef;
	}
}

sub create_context {	
	my($parameters) = @_;
	$parameters = Bio::KBase::utilities::args($parameters,["token","user"],{
		method => "unknown",
		provenance => [],
		setcontext => 1
	});
	my $context = LocalCallContext->new($parameters->{token}, $parameters->{user},$parameters->{provenance},$parameters->{method});
	if ($parameters->{setcontext} == 1) {
		Bio::KBase::utilities::set_context($context);
	}
	return $context;
}

sub set_context {
	my($context) = @_;
	$ctx = $context;
}

sub context {
	return $ctx;
}

sub token {
	return $ctx->token();
}

sub method {
	return $ctx->method();
}

sub provenance {
	return $ctx->provenance();
}

sub user_id {
	return $ctx->user_id();
}

sub timestamp {
	my ($reset) = @_;
	if (defined($reset) && $reset == 1) {
		$timestamp = DateTime->now()->datetime();
	}
	return $timestamp;	
}

{
    package LocalCallContext;
    use strict;
    sub new {
        my($class,$token,$user,$provenance,$method) = @_;
        my $self = {
            token => $token,
            user_id => $user,
            provenance => $provenance,
            method => $method
        };
        return bless $self, $class;
    }
    sub user_id {
        my($self) = @_;
        return $self->{user_id};
    }
    sub token {
        my($self) = @_;
        return $self->{token};
    }
    sub provenance {
        my($self) = @_;
        return $self->{provenance};
    }
    sub method {
        my($self) = @_;
        return $self->{method};
    }
    sub authenticated {
        return 1;
    }
    sub log_debug {
        my($self,$msg) = @_;
        print STDERR $msg."\n";
    }
    sub log_info {
        my($self,$msg) = @_;
        print STDERR $msg."\n";
    }
}

sub nameToSearchname {
	my ($InName) = @_;
	my $OriginalName = $InName;
	my $ending = "";
	if ($InName =~ m/-$/) {
		$ending = "-";
	}
	$InName = lc($InName);
	$InName =~ s/\s//g;
	$InName =~ s/,//g;
	$InName =~ s/-//g;
	$InName =~ s/_//g;
	$InName =~ s/\(//g;
	$InName =~ s/\)//g;
	$InName =~ s/\{//g;
	$InName =~ s/\}//g;
	$InName =~ s/\[//g;
	$InName =~ s/\]//g;
	$InName =~ s/\://g;
	$InName =~ s/�//g;
	$InName =~ s/'//g;
	$InName .= $ending;
	$InName =~ s/icacid/ate/g;
	if($OriginalName =~ /^an? /){
		$InName =~ s/^an?(.*)$/$1/;
	}
	return $InName;
}

1;
