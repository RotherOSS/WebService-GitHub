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

package Kernel::GenericInterface::Event::Validation::GitHubIssueNotCreated;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);

our @ObjectDependencies = ();

=head1 NAME

Kernel::GenericInterface::Event::Validation::GitHubIssueNotCreated - event condition: the ticket has no GitHub issue yet

=head1 DESCRIPTION

Condition module of type C<Module> for invoker events. It matches only if the dynamic field
C<GitHubIssueID> of the ticket is empty, so the invoker C<IssueCreate> of the example web service
F<var/webservices/examples/GitHubConnector.yml> creates only one issue per ticket, also if the
repository (C<GitHubIssueRepository>) is changed later or set by the import of an issue.

A condition "field is empty" is not possible with the condition types C<String> and C<Regexp>,
they never match an empty value.

    Condition => {
        1 => {
            Type   => 'and',
            Fields => {
                DynamicField_GitHubIssueID => {
                    Type  => 'Module',
                    Match => 'Kernel::GenericInterface::Event::Validation::GitHubIssueNotCreated',
                },
            },
        },
    },

=head1 PUBLIC INTERFACE

=head2 new()

Don't use the constructor directly, use the ObjectManager instead:

    my $ValidationObject = $Kernel::OM->Get('Kernel::GenericInterface::Event::Validation::GitHubIssueNotCreated');

=cut

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = bless {}, $Type;

    return $Self;
}

=head2 Validate()

Returns 1 if the ticket data has no value for C<DynamicField_GitHubIssueID>.

    my $NoIssue = $ValidationObject->Validate(
        Data => {
            TicketID                   => 123,
            DynamicField_GitHubIssueID => '',     # e.g. 'RotherOSS/otobo#123'
        },
    );

=cut

sub Validate {
    my ( $Self, %Param ) = @_;

    return if !IsHashRefWithData( $Param{Data} );

    my $IssueID = $Param{Data}->{DynamicField_GitHubIssueID};

    # multi value fields are serialized as array
    if ( ref $IssueID eq 'ARRAY' ) {
        $IssueID = join '', grep {defined} @{$IssueID};
    }

    return if IsStringWithData($IssueID);

    return 1;
}

1;
