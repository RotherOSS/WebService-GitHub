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

package Kernel::GenericInterface::Invoker::GitHub::IssuePoll;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);
use Kernel::GenericInterface::Invoker::GitHub::Common;

our $ObjectManagerDisabled = 1;

=head1 NAME

Kernel::GenericInterface::Invoker::GitHub::IssuePoll - poll GitHub issues and create or update tickets

=head1 DESCRIPTION

Meant to be called periodically, e.g. by the console command
C<Maint::GenericInterface::TriggerInvoker> as cron task of the daemon.

The outbound mapping builds the request, e.g. the query of C<GET /search/issues>
(organisation, label, time window). The inbound mapping converts the found issues into the
following structure, which is executed by this invoker:

    Issue => [
        {
            MatchDynamicField => { Name => 'OTOBOIssue-ExternalID', Value => 'RotherOSS/otobo#123' },

            # only used if no ticket is found
            Ticket       => { Title => '...', Queue => '...', Type => '...', State => 'new', Priority => '3 normal' },
            DynamicField => [ { Name => '...', Value => '...' }, { Name => '...', ConfigItemLookup => { ... } } ],
            Article      => { SenderType => 'customer', IsVisibleForCustomer => 1, From => '...', Subject => '...', Body => '...' },

            # only used for existing tickets
            StateSync => {
                IsClosed    => 1,                     # state of the issue
                ClosedState => 'closed successful',   # ticket state if the issue is closed
                OpenState   => 'open',                # ticket state if the issue was reopened
            },

            # invokers scheduled for the ticket afterwards, e.g. to import the comments
            FollowUp => [ { Invoker => 'CommentsGet', Data => { Owner => '...', Repo => '...', Number => 123 } } ],
        },
    ],

See Kernel::GenericInterface::Invoker::GitHub::Common for MatchDynamicField and DynamicField.

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

The request is built completely by the outbound mapping. The mapping is skipped for
empty data, so the trigger data (e.g. C<Dummy> of TriggerInvoker) is passed on and
replaced by the mapping.

=cut

sub PrepareRequest {
    my ( $Self, %Param ) = @_;

    my %Data = IsHashRefWithData( $Param{Data} ) ? %{ $Param{Data} } : ();

    # never pass empty data, otherwise the outbound mapping is not executed
    $Data{Invoker} = $Self->{Invoker};

    return {
        Success => 1,
        Data    => \%Data,
    };
}

=head2 HandleResponse()

Creates tickets for new open issues, updates the state of existing tickets and schedules
the follow-up invokers. Closed issues without a ticket are skipped.

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
    my %Count        = (
        Created => 0,
        Updated => 0,
        Skipped => 0,
    );

    ISSUE:
    for my $Issue ( $CommonObject->AsList( $Data->{Issue} ) ) {
        next ISSUE if !IsHashRefWithData($Issue);

        my $TicketID = $CommonObject->TicketFind(
            MatchDynamicField => $Issue->{MatchDynamicField},
        );

        if ($TicketID) {
            if ( $Self->_StateSync( TicketID => $TicketID, StateSync => $Issue->{StateSync} ) ) {
                $Count{Updated}++;
            }
        }
        else {

            # an issue that is already closed needs no ticket
            if ( IsHashRefWithData( $Issue->{StateSync} ) && $Issue->{StateSync}->{IsClosed} ) {
                $Count{Skipped}++;
                next ISSUE;
            }

            $TicketID = $Self->_TicketCreate( Issue => $Issue );

            if ( !$TicketID ) {
                $Count{Skipped}++;
                next ISSUE;
            }
            $Count{Created}++;
        }

        $CommonObject->FollowUpSchedule(
            TicketID => $TicketID,
            FollowUp => $Issue->{FollowUp},
        );
    }

    $Self->{DebuggerObject}->Info(
        Summary => "$Count{Created} tickets created, $Count{Updated} updated, $Count{Skipped} skipped",
    );

    return {
        Success => 1,
        Data    => \%Count,
    };
}

# Creates the ticket of a new issue with its dynamic fields and the first article.
# Returns nothing if the issue is skipped (e.g. no config item for a required lookup).
sub _TicketCreate {
    my ( $Self, %Param ) = @_;

    my $Issue        = $Param{Issue};
    my $CommonObject = $Self->{CommonObject};

    if ( !IsHashRefWithData( $Issue->{Ticket} ) ) {
        $Self->{DebuggerObject}->Error(
            Summary => 'Got no Ticket data from the mapping, issue skipped',
            Data    => $Issue,
        );
        return;
    }

    # resolve the dynamic field values first, a missing config item skips the issue
    my $DynamicFieldValues = $CommonObject->DynamicFieldValuesPrepare(
        DynamicField => $Issue->{DynamicField},
    );
    return if !$DynamicFieldValues;

    my %Ticket       = %{ $Issue->{Ticket} };
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

    my $TicketID = $TicketObject->TicketCreate(
        Title        => $Ticket{Title},
        Queue        => $Ticket{Queue},
        Type         => $Ticket{Type},
        State        => $Ticket{State} || 'new',
        Priority     => $Ticket{Priority} || '3 normal',
        Lock         => 'unlock',
        CustomerNo   => $Ticket{CustomerID},
        CustomerUser => $Ticket{CustomerUser},
        OwnerID      => 1,
        UserID       => 1,
    );

    if ( !$TicketID ) {
        $Self->{DebuggerObject}->Error(
            Summary => 'Could not create ticket',
            Data    => \%Ticket,
        );
        return;
    }

    $CommonObject->DynamicFieldValuesSet(
        ObjectID => $TicketID,
        Values   => $DynamicFieldValues,
    );

    $CommonObject->ArticleAdd(
        TicketID => $TicketID,
        Article  => $Issue->{Article},
    );

    $Self->{DebuggerObject}->Info(
        Summary => "Ticket $TicketID created for $Issue->{MatchDynamicField}->{Value}",
    );

    return $TicketID;
}

# Closes or reopens the ticket if the issue was closed or reopened.
# Returns 1 if the state was changed.
sub _StateSync {
    my ( $Self, %Param ) = @_;

    my $StateSync = $Param{StateSync};
    return 0 if !IsHashRefWithData($StateSync);

    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
    my %Ticket       = $TicketObject->TicketGet(
        TicketID => $Param{TicketID},
        UserID   => 1,
    );

    my $TicketIsClosed = $Ticket{StateType} eq 'closed' ? 1 : 0;
    my $IssueIsClosed  = $StateSync->{IsClosed}        ? 1 : 0;

    # nothing to do if ticket and issue are both open or both closed
    return 0 if $TicketIsClosed == $IssueIsClosed;

    my $NewState = $IssueIsClosed ? $StateSync->{ClosedState} : $StateSync->{OpenState};
    return 0 if !IsStringWithData($NewState);

    my $Success = $TicketObject->TicketStateSet(
        TicketID => $Param{TicketID},
        State    => $NewState,
        UserID   => 1,
    );

    if ( !$Success ) {
        $Self->{DebuggerObject}->Error(
            Summary => "Could not set state $NewState of ticket $Param{TicketID}",
        );
        return 0;
    }

    return 1;
}

1;

