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

use v5.24;
use strict;
use warnings;
use utf8;

# core modules

# CPAN modules
use Test2::V0;

# OTOBO modules
use Kernel::System::UnitTest::RegisterOM;    # set up $Kernel::OM
use Kernel::GenericInterface::Debugger;
use Kernel::GenericInterface::Invoker::GitHub::IssuePoll;

$Kernel::OM->ObjectParamAdd(
    'Kernel::System::UnitTest::Helper' => {
        RestoreDatabase => 1,
    },
);
my $HelperObject = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');
my $RandomID     = $HelperObject->GetRandomID();

my $TicketObject              = $Kernel::OM->Get('Kernel::System::Ticket');
my $ArticleObject             = $Kernel::OM->Get('Kernel::System::Ticket::Article');
my $DynamicFieldObject        = $Kernel::OM->Get('Kernel::System::DynamicField');
my $DynamicFieldBackendObject = $Kernel::OM->Get('Kernel::System::DynamicField::Backend');

# dynamic fields of the test, names with random ID
my %FieldName = (
    IssueID => "GitHubIssueID$RandomID",
    Labels  => "GitHubIssueLabels$RandomID",
);
my %FieldConfig;
for my $Field ( sort keys %FieldName ) {
    my $ID = $DynamicFieldObject->DynamicFieldAdd(
        Name       => $FieldName{$Field},
        Label      => $Field,
        FieldOrder => 99000,
        FieldType  => 'Text',
        ObjectType => 'Ticket',
        Config     => {
            DefaultValue => '',
            MultiValue   => ( $Field eq 'Labels' ? 1 : 0 ),
        },
        ValidID => 1,
        UserID  => 1,
    );
    ok( $ID, "dynamic field $FieldName{$Field} created" );

    $FieldConfig{$Field} = $DynamicFieldObject->DynamicFieldGet( ID => $ID );
}

my $DebuggerObject = Kernel::GenericInterface::Debugger->new(
    DebuggerConfig => {
        DebugThreshold => 'error',
        TestMode       => 1,
    },
    WebserviceID      => 1,
    CommunicationType => 'Requester',
);

my $InvokerObject = Kernel::GenericInterface::Invoker::GitHub::IssuePoll->new(
    DebuggerObject => $DebuggerObject,
    WebserviceID   => 1,
    Invoker        => 'IssuePoll',
);
isa_ok( $InvokerObject, 'Kernel::GenericInterface::Invoker::GitHub::IssuePoll' );

# the structure the inbound mapping produces for an issue
my $IssueData = sub {
    my %Param = @_;

    my $IssueID = "Owner/Repo$RandomID#$Param{Number}";

    return {
        MatchDynamicField => {
            Name  => $FieldName{IssueID},
            Value => $IssueID,
        },
        SkipCreate => $Param{SkipCreate} // 0,
        Ticket     => {
            Title    => "Issue $Param{Number}",
            Queue    => 'Raw',
            State    => 'new',
            Priority => '3 normal',
        },
        DynamicField => [
            {
                Name  => $FieldName{IssueID},
                Value => $IssueID,
            },
            {
                Name  => $FieldName{Labels},
                Value => $Param{Labels},
            },
        ],
        Article => {
            SenderType           => 'customer',
            IsVisibleForCustomer => 1,
            From                 => 'octocat (GitHub)',
            Subject              => "Issue $Param{Number}",
            Body                 => 'Body',
        },
        Update => {
            DynamicField => {
                Name  => $FieldName{Labels},
                Value => $Param{Labels},
            },
        },
        StateSync => {
            IsClosed    => $Param{IsClosed} // 0,
            ClosedState => 'closed successful',
            OpenState   => 'open',
        },
    };
};

my $Poll = sub {
    my @Issues = @_;

    my $Result = $InvokerObject->HandleResponse(
        ResponseSuccess => 1,
        Data            => {
            Issue => ( @Issues == 1 ? $Issues[0] : \@Issues ),    # like the XML mapping
        },
    );
    ok( $Result->{Success}, 'HandleResponse() successful' );

    return $Result->{Data};
};

my $TicketFind = sub {
    my ($Number) = @_;

    my @TicketIDs = $TicketObject->TicketSearch(
        Result                         => 'ARRAY',
        "DynamicField_$FieldName{IssueID}" => {
            Equals => "Owner/Repo$RandomID#$Number",
        },
        UserID => 1,
    );

    return @TicketIDs;
};

my $Labels = sub {
    my ($TicketID) = @_;

    my $Value = $DynamicFieldBackendObject->ValueGet(
        DynamicFieldConfig => $FieldConfig{Labels},
        ObjectID           => $TicketID,
    ) // [];

    return [ sort @{$Value} ];
};

subtest 'new open issue creates a ticket' => sub {
    my $Count = $Poll->( $IssueData->( Number => 1, Labels => [ 'bug', 'documentation' ] ) );
    is( $Count, { Created => 1, Updated => 0, Skipped => 0 }, 'counts' );

    my @TicketIDs = $TicketFind->(1);
    is( scalar @TicketIDs, 1, 'one ticket' );

    is( $Labels->( $TicketIDs[0] ), [ 'bug', 'documentation' ], 'labels set as multi value' );

    my @Articles = $ArticleObject->ArticleList( TicketID => $TicketIDs[0] );
    is( scalar @Articles, 1, 'first article created' );
};

subtest 'unchanged issue changes nothing' => sub {
    my $Count = $Poll->( $IssueData->( Number => 1, Labels => [ 'bug', 'documentation' ] ) );
    is( $Count, { Created => 0, Updated => 0, Skipped => 0 }, 'counts' );
    is( scalar $TicketFind->(1), 1, 'still one ticket' );
};

subtest 'changed labels update the ticket' => sub {
    my $Count = $Poll->( $IssueData->( Number => 1, Labels => 'bug' ) );    # a single value is a string
    is( $Count, { Created => 0, Updated => 1, Skipped => 0 }, 'counts' );

    my ($TicketID) = $TicketFind->(1);
    is( $Labels->($TicketID), ['bug'], 'labels updated' );

    $Count = $Poll->( $IssueData->( Number => 1, Labels => '' ) );    # no labels
    is( $Count, { Created => 0, Updated => 1, Skipped => 0 }, 'counts without labels' );
    is( $Labels->($TicketID), [], 'labels removed' );
};

subtest 'closed and reopened issue' => sub {
    my ($TicketID) = $TicketFind->(1);

    my $Count = $Poll->( $IssueData->( Number => 1, Labels => '', IsClosed => 1 ) );
    is( $Count, { Created => 0, Updated => 1, Skipped => 0 }, 'counts closed' );

    my %Ticket = $TicketObject->TicketGet( TicketID => $TicketID );
    is( $Ticket{State}, 'closed successful', 'ticket closed' );

    $Count = $Poll->( $IssueData->( Number => 1, Labels => '', IsClosed => 0 ) );
    is( $Count, { Created => 0, Updated => 1, Skipped => 0 }, 'counts reopened' );

    %Ticket = $TicketObject->TicketGet( TicketID => $TicketID );
    is( $Ticket{State}, 'open', 'ticket reopened' );
};

subtest 'issues without ticket that are skipped' => sub {
    my $Count = $Poll->(
        $IssueData->( Number => 2, Labels => '', SkipCreate => 1 ),
        $IssueData->( Number => 3, Labels => '', IsClosed   => 1 ),
    );
    is( $Count, { Created => 0, Updated => 0, Skipped => 2 }, 'counts' );
    is( scalar $TicketFind->(2), 0, 'no ticket for SkipCreate' );
    is( scalar $TicketFind->(3), 0, 'no ticket for a closed issue' );
};

subtest 'required config item lookup' => sub {
    my $Issue = $IssueData->( Number => 4, Labels => '' );
    push @{ $Issue->{DynamicField} }, {
        Name             => $FieldName{IssueID},
        ConfigItemLookup => {
            Class    => "NoClass$RandomID",
            Name     => 1,
            Value    => 'NoConfigItem',
            Required => 1,
        },
    };

    my $Count = $Poll->($Issue);
    is( $Count, { Created => 0, Updated => 0, Skipped => 1 }, 'issue skipped without config item' );
    is( scalar $TicketFind->(4), 0, 'no ticket' );
};

subtest 'error response' => sub {
    my $Result = $InvokerObject->HandleResponse(
        ResponseSuccess      => 0,
        ResponseErrorMessage => 'Bad credentials',
    );
    is( $Result->{Success},      0,                 'not successful' );
    is( $Result->{ErrorMessage}, 'Bad credentials', 'error message passed on' );
};

done_testing;
