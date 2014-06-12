package Im::Util::Meta;

use strict;
use warnings;

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
  get_meta has_meta set_meta create_meta
  add_attribute add_requires add_with
  install_attr install_attrs install_sub
);

use Im::Util qw(mutate);
use Package::Anonish::PP;
use Safe::Isa;

sub get_meta {
  my $thing = @_;
  return $thing->$_can('meta') ? $thing->meta : undef;
}

sub has_meta {
  my ($thing) = @_;
  return defined get_meta($thing);
}

sub set_meta {
  my ($package, $meta) = @_;
  if ($meta) {
    _pa_for($package)->add_method('meta', sub { $meta })
  } else {
    $meta = create_meta(package => $package);
    _pa_for($package)->add_method('meta', sub { $meta })
      unless has_meta($package);
  }
}

sub create_meta {
  my (%attrs) = @_;
  my %defaults = (type => 'unit');
	$defaults{units} = [$defaults{package}||()];
  return bless { %defaults, %attrs }, 'Im::Meta';
}

sub install_sub {
  my ($meta, $name, $code) = @_;
  my $pa = Package::Anonish::PP->new($meta->{'package'});
  $pa->add_method($name, $code);
}

sub install_attr {
  my ($meta, $name, %conf) = @_;
  $conf{init_arg} = $name
    unless exists $conf{init_arg};
  if ($conf{init_arg}) {
    if ($conf{builder}) {
			install_sub($meta, "_build_$name", $conf{builder});
			install_sub($meta, $name, sub {
        my $self = shift;
        install_sub($meta, $name, sub { shift->{$name} });
        mutate($self, sub {
          $_->{$name} = $self->can("_build_$name")->($self);
        });
        $self->{$name};
      });
    } else {
      croak("lazy attributes must have a supplied 'builder' (CODE ref)")
        if ($conf{lazy});
      install_sub ($meta, $name, sub { shift->{$name} });
    }
  }
  if ($conf{required}) {
		$conf{predicate} = 1
			unless exists $conf{predicate};
	}
  if ($conf{predicate}) {
    $conf{predicate} = $name
      if $conf{predicate} eq '1';
    install_sub($meta, $conf{predicate}, sub { defined shift->$name });
  }
}

sub install_attrs {
  my ($meta) = @_;
  foreach my $k (keys %{$meta->{'attrs'}}) {
    install_attr($meta, $k, %{$meta->{'attrs'}->{$k}});
  }
}

sub add_attribute {
  my ($meta, $name, %spec) = @_;
  my $new = clone($meta);
  my %attrs = %{$meta->{'attrs'} || {}};
  $attrs{$name} = {%spec};
  $new = mutate($new, sub {
    $_->{'attrs'} = {%attrs};
  });
  set_meta($meta->{'package'},$new);
}

sub add_requires {
  my ($meta, @names) = @_;
  my $new = clone($meta);
  my @requires = @{$meta->{'requires'} || []};
	foreach my $n (@names) {
		push @requires, $n
			unless grep $_ eq $n, @requires;
	}
  $new = mutate($new, sub {
    $_->{'requires'} = [@requires];
  });
  set_meta($meta->{'package'},$new);
}

sub add_with {
  my ($meta, @units) = @_;
  my $new = clone($meta);
  my @with = @{$meta->{'units'} || []};
  foreach my $u (@units) {
    push @with, $u
      unless (grep $_ eq $u, @with);
  }
  $new = mutate($new, sub {
    $_->{'with'} = [@with];
  });
  set_meta($meta->{'package'}, $new);
}

sub install_new {
  my ($meta) = @_;
	my %attrs = %{$meta->{'attrs'}};
	my @required;
	foreach my $k (keys %attrs) {
		if ($attrs{$k}->{'required'}) {
			push @required, $k;
		}
	}
	my $new = sub {
    my (%args) = @_;
		my @missing;
    foreach my $r (@required) {
			push @missing, $r
				unless defined $args{$r};
		}
		croak("The following required attributes are missing: " . join(", ", @missing))
			if @missing;
		return reify(units => [ $meta->{'package'} ], %args);
	};
	install_sub($meta->{'package'},'new', $new);
}
1
__END__
