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
use Kernel::GenericInterface::Invoker::GitHub::CommentsGet;

$Kernel::OM->ObjectParamAdd(
    'Kernel::System::UnitTest::Helper' => {
        RestoreDatabase => 1,
    },
);
my $HelperObject = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');
my $RandomID     = $HelperObject->GetRandomID();

my $TicketObject       = $Kernel::OM->Get('Kernel::System::Ticket');
my $ArticleObject      = $Kernel::OM->Get('Kernel::System::Ticket::Article');
my $DynamicFieldObject = $Kernel::OM->Get('Kernel::System::DynamicField');

# article field for the comment ID
my $CommentField = "GitHubCommentID$RandomID";
my $FieldID      = $DynamicFieldObject->DynamicFieldAdd(
    Name       => $CommentField,
    Label      => 'GitHub Comment',
    FieldOrder => 99000,
    FieldType  => 'Text',
    ObjectType => 'Article',
    Config     => {
        DefaultValue => '',
    },
    ValidID => 1,
    UserID  => 1,
);
ok( $FieldID, 'article dynamic field created' );

my $TicketID = $TicketObject->TicketCreate(
    Title    => "GitHub comments $RandomID",
    Queue    => 'Raw',
    Lock     => 'unlock',
    Priority => '3 normal',
    State    => 'new',
    OwnerID  => 1,
    UserID   => 1,
);
ok( $TicketID, 'ticket created' );

my $DebuggerObject = Kernel::GenericInterface::Debugger->new(
    DebuggerConfig => {
        DebugThreshold => 'error',
        TestMode       => 1,
    },
    WebserviceID      => 1,
    CommunicationType => 'Requester',
);

my $InvokerObject = Kernel::GenericInterface::Invoker::GitHub::CommentsGet->new(
    DebuggerObject => $DebuggerObject,
    WebserviceID   => 1,
    Invoker        => 'CommentsGet',
);
isa_ok( $InvokerObject, 'Kernel::GenericInterface::Invoker::GitHub::CommentsGet' );

subtest 'PrepareRequest' => sub {
    my $Result = $InvokerObject->PrepareRequest(
        Data => {
            Owner  => 'Owner',
            Repo   => 'Repo',
            Number => 7,
        },
    );
    is( $Result->{Success}, 0, 'TicketID is needed' );

    $Result = $InvokerObject->PrepareRequest(
        Data => {
            TicketID => $TicketID,
            Owner    => 'Owner',
            Repo     => 'Repo',
            Number   => 7,
        },
    );
    is(
        $Result,
        {
            Success => 1,
            Data    => {
                Owner  => 'Owner',
                Repo   => 'Repo',
                Number => 7,
            },
        },
        'TicketID is not sent to GitHub'
    );
};

# the structure the inbound mapping produces for a comment
my $Comment = sub {
    my ($ID) = @_;

    return {
        MatchDynamicField => {
            Name  => $CommentField,
            Value => $ID,
        },
        SenderType           => 'customer',
        IsVisibleForCustomer => 1,
        From                 => 'octocat (GitHub)',
        Subject              => "Comment $ID",
        Body                 => "Comment $ID",
        DynamicField         => {
            Name  => $CommentField,
            Value => $ID,
        },
    };
};

subtest 'comments are imported once' => sub {
    my $Result = $InvokerObject->HandleResponse(
        ResponseSuccess => 1,
        Data            => {
            Article => [ $Comment->(101), $Comment->(102) ],
        },
    );
    is( $Result->{Data}->{Created}, 2, 'two articles created' );

    $Result = $InvokerObject->HandleResponse(
        ResponseSuccess => 1,
        Data            => {
            Article => [ $Comment->(101), $Comment->(102), $Comment->(103) ],
        },
    );
    is( $Result->{Data}->{Created}, 1, 'only the new comment is imported' );

    my @Articles = $ArticleObject->ArticleList( TicketID => $TicketID );
    is( scalar @Articles, 3, 'three articles' );
};

subtest 'Markdown comment is stored as HTML article' => sub {
    my $Comment = $Comment->(104);
    $Comment->{Body}        = "Some **bold** text\n\n- one\n- two";
    $Comment->{ContentType} = 'text/markdown; charset=utf-8';

    my $Result = $InvokerObject->HandleResponse(
        ResponseSuccess => 1,
        Data            => {
            Article => [$Comment],
        },
    );
    is( $Result->{Data}->{Created}, 1, 'article created' );

    my @Articles = $ArticleObject->ArticleList( TicketID => $TicketID );
    my $ArticleBackendObject = $ArticleObject->BackendForArticle( %{ $Articles[-1] } );

    # OTOBO stores the HTML body as attachment 'file-2' and the plain text version in the article body
    my %AttachmentIndex = $ArticleBackendObject->ArticleAttachmentIndex(
        ArticleID    => $Articles[-1]->{ArticleID},
        OnlyHTMLBody => 1,
    );
    my ($HTMLBodyAttachmentID) = sort keys %AttachmentIndex;
    ok( $HTMLBodyAttachmentID, 'article has an HTML body' );

    my %Attachment = $ArticleBackendObject->ArticleAttachment(
        TicketID  => $TicketID,
        ArticleID => $Articles[-1]->{ArticleID},
        FileID    => $HTMLBodyAttachmentID,
    );
    like( $Attachment{Content}, qr{<strong>bold</strong>}, 'Markdown was converted to HTML' );
    like( $Attachment{Content}, qr{<li>two</li>},          'list was converted to HTML' );
};

subtest 'no comments' => sub {
    my $Result = $InvokerObject->HandleResponse(
        ResponseSuccess => 1,
        Data            => '',    # an empty result of the mapping
    );
    is( $Result->{Data}->{Created}, 0, 'nothing created' );
};

done_testing;
