#line 1
##############################################################################
#      $URL: http://perlcritic.tigris.org/svn/perlcritic/branches/Perl-Critic-PPI-1.204/lib/Perl/Critic.pm $
#     $Date: 2009-08-08 10:42:31 -0500 (Sat, 08 Aug 2009) $
#   $Author: clonezone $
# $Revision: 3482 $
##############################################################################

package Perl::Critic;

use 5.006001;
use strict;
use warnings;

use English qw(-no_match_vars);
use Readonly;

use base qw(Exporter);

use File::Spec;
use Scalar::Util qw(blessed);
use List::MoreUtils qw(firstidx);

use Perl::Critic::Exception::Configuration::Generic;
use Perl::Critic::Config;
use Perl::Critic::Violation;
use Perl::Critic::Document;
use Perl::Critic::Statistics;
use Perl::Critic::Utils qw{ :characters hashify };

#-----------------------------------------------------------------------------

our $VERSION = '1.103';

Readonly::Array our @EXPORT_OK => qw(critique);

#=============================================================================
# PUBLIC methods

sub new {
    my ( $class, %args ) = @_;
    my $self = bless {}, $class;
    $self->{_config} = $args{-config} || Perl::Critic::Config->new( %args );
    $self->{_stats} = Perl::Critic::Statistics->new();
    return $self;
}

#-----------------------------------------------------------------------------

sub config {
    my $self = shift;
    return $self->{_config};
}

#-----------------------------------------------------------------------------

sub add_policy {
    my ( $self, @args ) = @_;
    #Delegate to Perl::Critic::Config
    return $self->config()->add_policy( @args );
}

#-----------------------------------------------------------------------------

sub policies {
    my $self = shift;

    #Delegate to Perl::Critic::Config
    return $self->config()->policies();
}

#-----------------------------------------------------------------------------

sub statistics {
    my $self = shift;
    return $self->{_stats};
}

#-----------------------------------------------------------------------------

sub critique {  ## no critic (ArgUnpacking)

    #-------------------------------------------------------------------
    # This subroutine can be called as an object method or as a static
    # function.  In the latter case, the first argument can be a
    # hashref of configuration parameters that shall be used to create
    # an object behind the scenes.  Note that this object does not
    # persist.  In other words, it is not a singleton.  Here are some
    # of the ways this subroutine might get called:
    #
    # #Object style...
    # $critic->critique( $code );
    #
    # #Functional style...
    # critique( $code );
    # critique( {}, $code );
    # critique( {-foo => bar}, $code );
    #------------------------------------------------------------------

    my ( $self, $source_code ) = @_ >= 2 ? @_ : ( {}, $_[0] );
    $self = ref $self eq 'HASH' ? __PACKAGE__->new(%{ $self }) : $self;
    return if not defined $source_code;  # If no code, then nothing to do.

    my $doc = blessed($source_code) && $source_code->isa('Perl::Critic::Document') ?
        $source_code : Perl::Critic::Document->new($source_code);

    if ( 0 == $self->policies() ) {
        Perl::Critic::Exception::Configuration::Generic->throw(
            message => 'There are no enabled policies.',
        )
    }

    return $self->_gather_violations($doc);
}

#=============================================================================
# PRIVATE methods

sub _gather_violations {
    my ($self, $doc) = @_;

    # Disable exempt code lines, if desired
    if ( not $self->config->force() ) {
        $doc->process_annotations();
    }

    # Evaluate each policy
    my @policies = $self->config->policies();
    my @ordered_policies = _futz_with_policy_order(@policies);
    my @violations = map { _critique($_, $doc) } @ordered_policies;

    # Accumulate statistics
    $self->statistics->accumulate( $doc, \@violations );

    # If requested, rank violations by their severity and return the top N.
    if ( @violations && (my $top = $self->config->top()) ) {
        my $limit = @violations < $top ? $#violations : $top-1;
        @violations = Perl::Critic::Violation::sort_by_severity(@violations);
        @violations = ( reverse @violations )[ 0 .. $limit ];  #Slicing...
    }

    # Always return violations sorted by location
    return Perl::Critic::Violation->sort_by_location(@violations);
}

#=============================================================================
# PRIVATE functions

sub _critique {
    my ($policy, $doc) = @_;

    return if not $policy->prepare_to_scan_document($doc);

    my $maximum_violations = $policy->get_maximum_violations_per_document();
    return if defined $maximum_violations && $maximum_violations == 0;

    my @violations = ();

  TYPE:
    for my $type ( $policy->applies_to() ) {
        my @elements;
        if ($type eq 'PPI::Document') {
            @elements = ($doc);
        }
        else {
            @elements = @{ $doc->find($type) || [] };
        }

      ELEMENT:
        for my $element (@elements) {

            # Evaluate the policy on this $element.  A policy may
            # return zero or more violations.  We only want the
            # violations that occur on lines that have not been
            # disabled.

          VIOLATION:
            for my $violation ( $policy->violates( $element, $doc ) ) {

                my $line = $violation->location()->[0];
                if ( $doc->line_is_disabled_for_policy($line, $policy) ) {
                    $doc->add_suppressed_violation($violation);
                    next VIOLATION;
                }

                push @violations, $violation;
                last TYPE if defined $maximum_violations and @violations >= $maximum_violations;
            }
        }
    }

    return @violations;
}

#-----------------------------------------------------------------------------

sub _futz_with_policy_order {

    # The ProhibitUselessNoCritic policy is another special policy.  It
    # deals with the violations that *other* Policies produce.  Therefore
    # it needs to be run *after* all the other Policies.  TODO: find
    # a way for Policies to express an ordering preference somehow.

    my @policy_objects = @_;
    my $magical_policy_name = 'Perl::Critic::Policy::Miscellanea::ProhibitUselessNoCritic';
    my $idx = firstidx {ref $_ eq $magical_policy_name} @policy_objects;
    push @policy_objects, splice @policy_objects, $idx, 1;
    return @policy_objects;
}

#-----------------------------------------------------------------------------

1;



__END__

#line 1003

##############################################################################
# Local Variables:
#   mode: cperl
#   cperl-indent-level: 4
#   fill-column: 78
#   indent-tabs-mode: nil
#   c-indentation-style: bsd
# End:
# ex: set ts=8 sts=4 sw=4 tw=78 ft=perl expandtab shiftround :
