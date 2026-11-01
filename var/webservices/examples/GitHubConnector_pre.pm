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

package var::webservices::examples::GitHubConnector_pre;

use strict;
use warnings;
use utf8;

use parent qw(var::webservices::examples::Base);

our @ObjectDependencies = ();

=head1 NAME

var::webservices::examples::GitHubConnector_pre - dynamic fields of the Ready2Adopt web service GitHubConnector

=head1 DESCRIPTION

Executed by the import of the Ready2Adopt web service F<GitHubConnector.yml>
(Admin, Web Services, Add web service). Creates the dynamic fields used by the mappings,
existing fields with the same name, object type and field type are kept.

=cut

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {%Param};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my @DynamicFields = (
        {
            Name       => 'GitHubIssueID',
            Label      => 'GitHub Issue',
            FieldType  => 'Text',
            ObjectType => 'Ticket',
            FieldOrder => 10000,
            Config     => {
                DefaultValue => '',
                Tooltip      => 'Issue on GitHub, e.g. Owner/Repository#123. Set by the web service, used to find the ticket of an issue.',
            },
        },
        {
            Name       => 'GitHubIssueURL',
            Label      => 'GitHub Issue Link',
            FieldType  => 'Text',
            ObjectType => 'Ticket',
            FieldOrder => 10001,
            Config     => {
                DefaultValue => '',
                Link         => '[% Data.Value %]',
                Tooltip      => 'Link to the issue on GitHub. Set by the web service.',
            },
        },
        {
            Name       => 'GitHubIssueRepository',
            Label      => 'GitHub Repository',
            FieldType  => 'Text',
            ObjectType => 'Ticket',
            FieldOrder => 10002,
            Config     => {
                DefaultValue => '',
                Link         => 'https://github.com/[% Data.Value | url %]',
                RegExList    => [
                    {
                        Value        => '^[^/\s]+/[^/\s]+$',
                        ErrorMessage => 'Owner/Repository, e.g. RotherOSS/otobo',
                    },
                ],
                Tooltip => 'Owner/Repository, e.g. RotherOSS/otobo. Creates an issue on GitHub if the ticket has none yet.',
            },
        },
        {
            Name       => 'GitHubIssueLabels',
            Label      => 'GitHub Labels',
            FieldType  => 'Text',
            ObjectType => 'Ticket',
            FieldOrder => 10003,
            Config     => {
                DefaultValue => '',
                MultiValue   => 1,
                Tooltip      => 'Labels of the GitHub issue, for information only. Updated by the web service.',
            },
        },
        {
            Name       => 'GitHubCommentID',
            Label      => 'GitHub Comment',
            FieldType  => 'Text',
            ObjectType => 'Article',
            FieldOrder => 10004,
            Config     => {
                DefaultValue => '',
                Tooltip      => 'ID of the GitHub comment the article was imported from. Set by the web service.',
            },
        },
    );

    return $Self->DynamicFieldsAdd(
        DynamicFieldList => \@DynamicFields,
    );
}

1;
