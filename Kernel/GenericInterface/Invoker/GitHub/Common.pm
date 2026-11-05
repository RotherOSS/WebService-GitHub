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

package Kernel::GenericInterface::Invoker::GitHub::Common;

use strict;
use warnings;

use Kernel::System::VariableCheck qw(:all);

our $ObjectManagerDisabled = 1;

=head1 NAME

Kernel::GenericInterface::Invoker::GitHub::Common - common functions of the GitHub invokers

=head1 DESCRIPTION

The GitHub invokers do not know anything about the tickets they create. Which queue, type,
dynamic fields etc. are used is defined completely by the inbound XSLT mapping of the invoker.
This module executes the data structure produced by the mapping:

    MatchDynamicField => {                      # find an existing ticket / article
        Name  => 'MyExternalID',
        Value => 'RotherOSS/otobo#123',
    },
    DynamicField => [                           # values to set
        {
            Name  => 'MyField',
            Value => 'some value',
        },
        {
            Name  => 'MyMultiValueField',        # fields with MultiValue get a list,
            Value => [ 'value 1', 'value 2' ],  # a single value or '' are converted
        },
        {
            Name             => 'MyConfigItemReference',
            ConfigItemLookup => {               # the value is the ID of the found config item
                Class        => 'Software',
                DynamicField => 'MyGitHubRepositoryField',   # or Name => 'config item name'
                Value        => 'otobo',
                Required     => 1,              # skip the issue if no config item is found
            },
        },
    ],

=head1 PUBLIC INTERFACE

=head2 new()

    my $CommonObject = Kernel::GenericInterface::Invoker::GitHub::Common->new(
        DebuggerObject => $DebuggerObject,
        WebserviceID   => 1,
        Invoker        => 'IssuePoll',
    );

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

    return $Self;
}

=head2 AsList()

The data converted back from XML contains a hash for a single element and an array for
several elements of the same name. AsList() always returns a list.

    my @Issues = $CommonObject->AsList( $Data->{Issue} );

=cut

sub AsList {
    my ( $Self, $Value ) = @_;

    return () if !defined $Value;
    return () if $Value eq '';
    return @{$Value} if ref $Value eq 'ARRAY';

    return ($Value);
}

=head2 TicketFind()

Returns the ID of the ticket with the given dynamic field value, or nothing.

    my $TicketID = $CommonObject->TicketFind(
        MatchDynamicField => {
            Name  => 'GitHubIssueID',
            Value => 'RotherOSS/otobo#3',
        },
    );

=cut

sub TicketFind {
    my ( $Self, %Param ) = @_;

    my $Match = $Param{MatchDynamicField};
    return if !IsHashRefWithData($Match);
    return if !IsStringWithData( $Match->{Name} );
    return if !IsStringWithData( $Match->{Value} );

    my @TicketIDs = $Kernel::OM->Get('Kernel::System::Ticket')->TicketSearch(
        Result                    => 'ARRAY',
        Limit                     => 2,
        "DynamicField_$Match->{Name}" => {
            Equals => $Match->{Value},
        },
        UserID => 1,
    );

    if ( @TicketIDs > 1 ) {
        $Self->{DebuggerObject}->Notice(
            Summary => "More than one ticket with $Match->{Name} = $Match->{Value}, the first one is used",
        );
    }

    return $TicketIDs[0];
}

=head2 DynamicFieldValuesPrepare()

Resolves the values of a dynamic field list (config item lookups). Returns an array
reference of hashes with Name and Value, or nothing if a required lookup failed.

    my $Values = $CommonObject->DynamicFieldValuesPrepare(
        DynamicField => $Issue->{DynamicField},
    );

=cut

sub DynamicFieldValuesPrepare {
    my ( $Self, %Param ) = @_;

    my @Values;

    DYNAMICFIELD:
    for my $DynamicField ( $Self->AsList( $Param{DynamicField} ) ) {
        next DYNAMICFIELD if !IsHashRefWithData($DynamicField);
        next DYNAMICFIELD if !IsStringWithData( $DynamicField->{Name} );

        # plain value
        if ( !IsHashRefWithData( $DynamicField->{ConfigItemLookup} ) ) {
            push @Values, {
                Name  => $DynamicField->{Name},
                Value => $DynamicField->{Value} // '',
            };
            next DYNAMICFIELD;
        }

        # value is the ID of a config item
        my $Lookup       = $DynamicField->{ConfigItemLookup};
        my $ConfigItemID = $Self->ConfigItemLookup( %{$Lookup} );

        if ( !$ConfigItemID ) {
            my $Description = "$Lookup->{Class}: " . ( $Lookup->{DynamicField} // 'Name' ) . " = " . ( $Lookup->{Value} // '' );

            # without the config item the data can not be created
            if ( $Lookup->{Required} ) {
                $Self->{DebuggerObject}->Notice(
                    Summary => "No config item found for $DynamicField->{Name} ($Description), skipped",
                );
                return;
            }

            $Self->{DebuggerObject}->Debug(
                Summary => "No config item found for $DynamicField->{Name} ($Description), field not set",
            );
            next DYNAMICFIELD;
        }

        push @Values, {
            Name  => $DynamicField->{Name},
            Value => $ConfigItemID,
        };
    }

    return \@Values;
}

=head2 ConfigItemLookup()

Returns the ID of the config item of a class with a given name or dynamic field value.
Needs the CMDB (Kernel::System::ITSMConfigItem).

    my $ConfigItemID = $CommonObject->ConfigItemLookup(
        Class        => 'Software',
        DynamicField => 'MyGitHubRepositoryField',    # or Name => 1 to search the name
        Value        => 'otobo',
    );

=cut

sub ConfigItemLookup {
    my ( $Self, %Param ) = @_;

    return if !IsStringWithData( $Param{Class} );
    return if !IsStringWithData( $Param{Value} );

    # the CMDB is optional, it is only needed for the lookup
    return if !$Kernel::OM->Get('Kernel::System::Main')->Require(
        'Kernel::System::ITSMConfigItem',
        Silent => 1,
    );

    my %Search = (
        Classes => [ $Param{Class} ],
        Result  => 'ARRAY',
        Limit   => 2,
        UserID  => 1,
    );

    if ( IsStringWithData( $Param{DynamicField} ) ) {
        $Search{"DynamicField_$Param{DynamicField}"} = {
            Equals => $Param{Value},
        };
    }
    else {
        $Search{Name} = $Param{Value};
    }

    my @ConfigItemIDs = $Kernel::OM->Get('Kernel::System::ITSMConfigItem')->ConfigItemSearch(%Search);

    return $ConfigItemIDs[0];
}

=head2 DynamicFieldValuesSet()

Sets dynamic field values of a ticket or an article.

    my $Success = $CommonObject->DynamicFieldValuesSet(
        ObjectID => 123,                        # TicketID or ArticleID
        Values   => [ { Name => 'MyField', Value => 'some value' } ],
    );

=cut

sub DynamicFieldValuesSet {
    my ( $Self, %Param ) = @_;

    my $DynamicFieldObject        = $Kernel::OM->Get('Kernel::System::DynamicField');
    my $DynamicFieldBackendObject = $Kernel::OM->Get('Kernel::System::DynamicField::Backend');

    my $Success = 1;

    VALUE:
    for my $Value ( @{ $Param{Values} // [] } ) {
        my $DynamicFieldConfig = $DynamicFieldObject->DynamicFieldGet(
            Name => $Value->{Name},
        );

        if ( !IsHashRefWithData($DynamicFieldConfig) ) {
            $Self->{DebuggerObject}->Error(
                Summary => "Dynamic field $Value->{Name} not found",
            );
            $Success = 0;
            next VALUE;
        }

        my $ValueSet = $DynamicFieldBackendObject->ValueSet(
            DynamicFieldConfig => $DynamicFieldConfig,
            ObjectID           => $Param{ObjectID},
            Value              => $Self->_DynamicFieldValueNormalize(
                DynamicFieldConfig => $DynamicFieldConfig,
                Value              => $Value->{Value},
            ),
            UserID => 1,
        );

        if ( !$ValueSet ) {
            $Self->{DebuggerObject}->Error(
                Summary => "Could not set dynamic field $Value->{Name} of object $Param{ObjectID}",
                Data    => $Value,
            );
            $Success = 0;
        }
    }

    return $Success;
}

=head2 DynamicFieldValuesUpdate()

Sets only the dynamic field values that differ from the current values, so that unchanged
values create no history entries and no events. Returns the number of changed values.

    my $Changed = $CommonObject->DynamicFieldValuesUpdate(
        ObjectID => 123,                        # TicketID or ArticleID
        Values   => [ { Name => 'MyField', Value => 'some value' } ],
    );

=cut

sub DynamicFieldValuesUpdate {
    my ( $Self, %Param ) = @_;

    my $DynamicFieldObject        = $Kernel::OM->Get('Kernel::System::DynamicField');
    my $DynamicFieldBackendObject = $Kernel::OM->Get('Kernel::System::DynamicField::Backend');

    my @ChangedValues;

    VALUE:
    for my $Value ( @{ $Param{Values} // [] } ) {
        my $DynamicFieldConfig = $DynamicFieldObject->DynamicFieldGet(
            Name => $Value->{Name},
        );

        # unknown fields are reported by DynamicFieldValuesSet()
        if ( !IsHashRefWithData($DynamicFieldConfig) ) {
            push @ChangedValues, $Value;
            next VALUE;
        }

        my $OldValue = $DynamicFieldBackendObject->ValueGet(
            DynamicFieldConfig => $DynamicFieldConfig,
            ObjectID           => $Param{ObjectID},
        );
        my $NewValue = $Self->_DynamicFieldValueNormalize(
            DynamicFieldConfig => $DynamicFieldConfig,
            Value              => $Value->{Value},
        );

        # compare as list of strings, single values and multi values alike
        my $OldString = join "\n", $Self->AsList($OldValue);
        my $NewString = join "\n", $Self->AsList($NewValue);
        next VALUE if $OldString eq $NewString;

        push @ChangedValues, $Value;
    }

    return 0 if !@ChangedValues;

    $Self->DynamicFieldValuesSet(
        ObjectID => $Param{ObjectID},
        Values   => \@ChangedValues,
    );

    return scalar @ChangedValues;
}

=head2 ArticleAdd()

Creates an article (default channel Internal) and sets its dynamic fields.

    my $ArticleID = $CommonObject->ArticleAdd(
        TicketID => 123,
        Article  => {
            CommunicationChannel => 'Internal',     # optional, default Internal
            SenderType           => 'customer',
            IsVisibleForCustomer => 1,
            From                 => 'octocat (GitHub)',
            Subject              => 'Comment',
            Body                 => 'Text',
            ContentType          => 'text/plain; charset=utf-8',   # optional, text/markdown is converted to HTML
            HistoryType          => 'AddNote',                     # optional
            DynamicField         => [ ... ],                       # optional
        },
    );

=cut

sub ArticleAdd {
    my ( $Self, %Param ) = @_;

    my $Article = $Param{Article};
    return if !IsHashRefWithData($Article);

    my $DynamicFieldValues = $Self->DynamicFieldValuesPrepare(
        DynamicField => $Article->{DynamicField},
    );
    return if !$DynamicFieldValues;

    my $ArticleBackendObject = $Kernel::OM->Get('Kernel::System::Ticket::Article')->BackendForChannel(
        ChannelName => $Article->{CommunicationChannel} || 'Internal',
    );

    my $Body        = $Article->{Body} // '';
    my $ContentType = $Article->{ContentType} || 'text/plain; charset=utf-8';

    # GitHub delivers issue and comment texts as Markdown. With the content type text/markdown the body
    # is converted to HTML and stored as HTML article. Kernel::System::Markdown comes with the required
    # package Webservice-Markdown.
    if ( $ContentType =~ m{\Atext/markdown}i ) {

        my $HTMLBody = $Kernel::OM->Get('Kernel::System::Markdown')->ToHTML(
            String => $Body,
        );

        # the conversion fails only when the CPAN module Markdown::Perl is missing, the error has been logged
        if ( !defined $HTMLBody ) {
            $Self->{DebuggerObject}->Error(
                Summary => "Markdown of the article could not be converted to HTML, no article created for ticket $Param{TicketID}",
                Data    => $Article,
            );
            return;
        }

        $Body = $HTMLBody;
        $ContentType =~ s{\Atext/markdown}{text/html}i;
    }

    my $ArticleID = $ArticleBackendObject->ArticleCreate(
        TicketID             => $Param{TicketID},
        SenderType           => $Article->{SenderType} || 'customer',
        IsVisibleForCustomer => $Article->{IsVisibleForCustomer} ? 1 : 0,
        From                 => $Article->{From},
        Subject              => $Article->{Subject},
        Body                 => $Body,
        ContentType          => $ContentType,
        HistoryType          => $Article->{HistoryType} || 'AddNote',
        HistoryComment       => "Imported by web service invoker $Self->{Invoker}",
        UserID               => 1,
    );

    if ( !$ArticleID ) {
        $Self->{DebuggerObject}->Error(
            Summary => "Could not create article for ticket $Param{TicketID}",
            Data    => $Article,
        );
        return;
    }

    $Self->DynamicFieldValuesSet(
        ObjectID => $ArticleID,
        Values   => $DynamicFieldValues,
    );

    return $ArticleID;
}

=head2 ArticleExists()

Checks if an article of the ticket has the given dynamic field value.

    my $Exists = $CommonObject->ArticleExists(
        TicketID          => 123,
        MatchDynamicField => {
            Name  => 'GitHubCommentID',
            Value => '6544623469',
        },
    );

=cut

sub ArticleExists {
    my ( $Self, %Param ) = @_;

    my $Match = $Param{MatchDynamicField};
    return 0 if !IsHashRefWithData($Match);
    return 0 if !IsStringWithData( $Match->{Value} );

    my $ArticleObject = $Kernel::OM->Get('Kernel::System::Ticket::Article');

    for my $Article ( $ArticleObject->ArticleList( TicketID => $Param{TicketID} ) ) {
        my %ArticleData = $ArticleObject->BackendForArticle( %{$Article} )->ArticleGet(
            TicketID      => $Param{TicketID},
            ArticleID     => $Article->{ArticleID},
            DynamicFields => 1,
        );

        my $Value = $ArticleData{"DynamicField_$Match->{Name}"} // '';
        return 1 if $Value eq $Match->{Value};
    }

    return 0;
}

=head2 FollowUpSchedule()

Schedules further invokers of the same web service for a ticket, e.g. to import the comments
of an issue. The TicketID is added to the data.

    $CommonObject->FollowUpSchedule(
        TicketID => 123,
        FollowUp => [
            {
                Invoker => 'CommentsGet',
                Data    => { Owner => 'RotherOSS', Repo => 'otobo', Number => 123 },
            },
        ],
    );

=cut

sub FollowUpSchedule {
    my ( $Self, %Param ) = @_;

    FOLLOWUP:
    for my $FollowUp ( $Self->AsList( $Param{FollowUp} ) ) {
        next FOLLOWUP if !IsHashRefWithData($FollowUp);
        next FOLLOWUP if !IsStringWithData( $FollowUp->{Invoker} );

        my %Data = IsHashRefWithData( $FollowUp->{Data} ) ? %{ $FollowUp->{Data} } : ();
        $Data{TicketID} = $Param{TicketID};

        my $TaskID = $Kernel::OM->Get('Kernel::System::Scheduler')->TaskAdd(
            Type     => 'GenericInterface',
            Name     => "Invoker-$FollowUp->{Invoker}",
            Attempts => 3,
            Data     => {
                WebserviceID => $Self->{WebserviceID},
                Invoker      => $FollowUp->{Invoker},
                Data         => \%Data,
            },
        );

        if ( !$TaskID ) {
            $Self->{DebuggerObject}->Error(
                Summary => "Could not schedule invoker $FollowUp->{Invoker} for ticket $Param{TicketID}",
            );
        }
    }

    return 1;
}

# Multi value fields need an array reference. The mapping returns a single value as string
# and no value as empty string, both are converted to a list.
sub _DynamicFieldValueNormalize {
    my ( $Self, %Param ) = @_;

    return $Param{Value} if !$Param{DynamicFieldConfig}->{Config}->{MultiValue};

    my @Values = grep { $_ ne '' } $Self->AsList( $Param{Value} );

    return \@Values;
}

1;
