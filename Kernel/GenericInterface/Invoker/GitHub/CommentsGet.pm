# --
# OTOBO is a web-based ticketing system for service organisations.
# --
# Copyright (C) 2019-2026 Rother OSS GmbH, https://otobo.io/
# --
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later version.
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
# --

package Kernel::GenericInterface::Invoker::GitHub::CommentsGet;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);
use Kernel::GenericInterface::Invoker::GitHub::Common;

our $ObjectManagerDisabled = 1;

=head1 NAME

Kernel::GenericInterface::Invoker::GitHub::CommentsGet - import the comments of a GitHub issue as articles

=head1 DESCRIPTION

Usually scheduled by Kernel::GenericInterface::Invoker::GitHub::IssuePoll for a ticket.
The data contains the C<TicketID> and the values for the route, e.g.
C</repos/:Owner/:Repo/issues/:Number/comments>.

The inbound mapping converts the comments into the following structure. Articles whose
C<MatchDynamicField> value already exists in the ticket are skipped, so a comment is
imported only once.

    Article => [
        {
            MatchDynamicField    => { Name => 'OTOBOIssue-ExternalCommentID', Value => '6544623469' },
            SenderType           => 'customer',
            IsVisibleForCustomer => 1,
            From                 => 'octocat (GitHub)',
            Subject              => '...',
            Body                 => '...',
            DynamicField         => [ { Name => 'OTOBOIssue-ExternalCommentID', Value => '6544623469' } ],
        },
    ],

=head1 PUBLIC INTERFACE

=head2 new()

usually, you want to create an instance of this
by using Kernel::GenericInterface::Invoker->new();

=cut

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = bless {}, $Type;

    for my $Needed (qw(DebuggerObject WebserviceID Invoker)) {
        if ( !$Param{$Needed} ) {
            return {
                Success      => 0,
                ErrorMessage => "Got no $Needed!",
            };
        }

        $Self->{$Needed} = $Param{$Needed};
    }

    $Self->{CommonObject} = Kernel::GenericInterface::Invoker::GitHub::Common->new( %{$Self} );

    return $Self;
}

=head2 PrepareRequest()

Remembers the TicketID and passes the remaining data (route values) on.

=cut

sub PrepareRequest {
    my ( $Self, %Param ) = @_;

    my %Data = IsHashRefWithData( $Param{Data} ) ? %{ $Param{Data} } : ();

    if ( !IsPositiveInteger( $Data{TicketID} ) ) {
        return {
            Success      => 0,
            ErrorMessage => 'Got no TicketID!',
        };
    }

    # the TicketID is needed for the response only, it must not be sent to GitHub
    $Self->{TicketID} = delete $Data{TicketID};

    return {
        Success => 1,
        Data    => \%Data,
    };
}

=head2 HandleResponse()

Creates an article for every comment that is not imported yet.

=cut

sub HandleResponse {
    my ( $Self, %Param ) = @_;

    if ( !$Param{ResponseSuccess} ) {
        return {
            Success      => 0,
            ErrorMessage => $Param{ResponseErrorMessage} || 'Got no successful response',
        };
    }

    # an empty result (e.g. no comments) is converted to an empty string by the mapping
    my $Data = IsHashRefWithData( $Param{Data} ) ? $Param{Data} : {};

    my $CommonObject = $Self->{CommonObject};
    my $Created      = 0;

    ARTICLE:
    for my $Article ( $CommonObject->AsList( $Data->{Article} ) ) {
        next ARTICLE if !IsHashRefWithData($Article);

        next ARTICLE if $CommonObject->ArticleExists(
            TicketID          => $Self->{TicketID},
            MatchDynamicField => $Article->{MatchDynamicField},
        );

        my $ArticleID = $CommonObject->ArticleAdd(
            TicketID => $Self->{TicketID},
            Article  => $Article,
        );
        $Created++ if $ArticleID;
    }

    $Self->{DebuggerObject}->Info(
        Summary => "$Created articles created for ticket $Self->{TicketID}",
    );

    return {
        Success => 1,
        Data    => {
            Created => $Created,
        },
    };
}

1;
