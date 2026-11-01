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

package Kernel::Language::de_WebServiceGitHub;

use strict;
use warnings;
use utf8;

sub Data {
    my $Self = shift;

    # SysConfig
    $Self->{Translation}->{'GenericInterface module registration for the GitHub invoker IssuePoll. Creates and updates tickets from the GitHub issues returned by the inbound mapping.'} =
        'GenericInterface-Modulregistrierung für den GitHub-Invoker IssuePoll. Legt Tickets aus den GitHub-Issues des eingehenden Mappings an und aktualisiert sie.';
    $Self->{Translation}->{'GenericInterface module registration for the GitHub invoker CommentsGet. Imports the comments of a GitHub issue as articles of a ticket.'} =
        'GenericInterface-Modulregistrierung für den GitHub-Invoker CommentsGet. Importiert die Kommentare eines GitHub-Issues als Artikel eines Tickets.';
    $Self->{Translation}->{'Polls GitHub issues every 5 minutes. Params are the name of the web service (default: the Ready2Adopt web service GitHubConnector) and the name of the invoker of type GitHub::IssuePoll.'} =
        'Ruft alle 5 Minuten die GitHub-Issues ab. Params sind der Name des Webservice (Standard: der Ready2Adopt-Webservice GitHubConnector) und der Name des Invokers vom Typ GitHub::IssuePoll.';

    # Dynamic fields of the Ready2Adopt web service GitHubConnector
    $Self->{Translation}->{'GitHub Issue'} = 'GitHub-Issue';
    $Self->{Translation}->{'Issue on GitHub, e.g. Owner/Repository#123. Set by the web service, used to find the ticket of an issue.'} =
        'Issue auf GitHub, z. B. Owner/Repository#123. Wird vom Webservice gesetzt und dient zum Finden des Tickets zu einem Issue.';
    $Self->{Translation}->{'GitHub Issue Link'} = 'Link zum GitHub-Issue';
    $Self->{Translation}->{'Link to the issue on GitHub. Set by the web service.'} = 'Link zum Issue auf GitHub. Wird vom Webservice gesetzt.';
    $Self->{Translation}->{'GitHub Repository'} = 'GitHub-Repository';
    $Self->{Translation}->{'Owner/Repository, e.g. RotherOSS/otobo. Creates an issue on GitHub if the ticket has none yet.'} =
        'Owner/Repository, z. B. RotherOSS/otobo. Legt ein Issue auf GitHub an, wenn das Ticket noch keines hat.';
    $Self->{Translation}->{'Owner/Repository, e.g. RotherOSS/otobo'} = 'Owner/Repository, z. B. RotherOSS/otobo';
    $Self->{Translation}->{'GitHub Labels'} = 'GitHub-Labels';
    $Self->{Translation}->{'Labels of the GitHub issue, for information only. Updated by the web service.'} =
        'Labels des GitHub-Issues, nur zur Information. Werden vom Webservice aktualisiert.';
    $Self->{Translation}->{'GitHub Comment'} = 'GitHub-Kommentar';
    $Self->{Translation}->{'ID of the GitHub comment the article was imported from. Set by the web service.'} =
        'ID des GitHub-Kommentars, aus dem der Artikel importiert wurde. Wird vom Webservice gesetzt.';

    return 1;
}

1;
