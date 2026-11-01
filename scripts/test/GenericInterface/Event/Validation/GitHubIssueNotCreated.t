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

my $ValidationObject = $Kernel::OM->Get('Kernel::GenericInterface::Event::Validation::GitHubIssueNotCreated');

my @Tests = (
    {
        Name   => 'no data',
        Data   => undef,
        Result => undef,
    },
    {
        Name   => 'field missing',
        Data   => { TicketID => 1 },
        Result => 1,
    },
    {
        Name   => 'field empty',
        Data   => { TicketID => 1, DynamicField_GitHubIssueID => '' },
        Result => 1,
    },
    {
        Name   => 'issue exists',
        Data   => { TicketID => 1, DynamicField_GitHubIssueID => 'RotherOSS/otobo#123' },
        Result => undef,
    },
    {
        Name   => 'issue exists, serialized as array',
        Data   => { TicketID => 1, DynamicField_GitHubIssueID => ['RotherOSS/otobo#123'] },
        Result => undef,
    },
);

for my $Test (@Tests) {
    is(
        scalar $ValidationObject->Validate( Data => $Test->{Data} ),
        $Test->{Result},
        $Test->{Name},
    );
}

done_testing;
