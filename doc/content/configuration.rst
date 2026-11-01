*************
Configuration
*************

System Requirements
-------------------

Framework
    OTOBO 11.1.x

Packages
    No other packages are needed. ``ITSMConfigurationManagement`` is only needed for the
    optional ``ConfigItemLookup`` of dynamic fields.

GitHub
    A token (fine-grained personal access token or token of a GitHub App) with read and write
    access to the issues of the repositories. It is recommended to use a separate GitHub account
    for the token (bot account), see ``BotLogin`` below.


.. _ready2adopt-web-service:

Ready2Adopt Web Service
-----------------------

1. Go to *Admin → Web Services → Add Web Service* and import the Ready2Adopt web service
   **GitHubConnector**. The import creates the following dynamic fields, existing fields with
   the same name and type are kept:

   ========================= ======== ============================================================
   Dynamic field             Object   Content
   ========================= ======== ============================================================
   ``GitHubIssueID``         Ticket   Issue, e.g. ``RotherOSS/otobo#123``, finds the ticket of an issue
   ``GitHubIssueURL``        Ticket   Link to the issue
   ``GitHubIssueRepository`` Ticket   Repository ``Owner/Repository``, creates the issue of a ticket
   ``GitHubIssueLabels``     Ticket   Labels of the issue (multi value), information only
   ``GitHubCommentID``       Article  ID of the imported comment, prevents duplicates
   ========================= ======== ============================================================

   A web service file imported with *Import web service* creates no dynamic fields. In this case
   create the fields manually.

2. Transport (*Configure* of the requester transport HTTP::REST), additional headers: replace
   ``CHANGE-ME`` in ``Authorization: Bearer CHANGE-ME`` with the token.

3. Replace ``CHANGE-ME`` in the XSLT mappings:

   - ``IssuePoll``, outbound: ``Organization``, the GitHub organization (or user) of the
     repositories.
   - ``IssuePoll`` and ``CommentsGet``, inbound: ``BotLogin``, the GitHub account of the token.
     Issues and comments of this account were created by OTOBO itself. They are not imported
     again, existing tickets of these issues are still updated.

4. Optional: adapt queue, type, state and priority of new tickets in the inbound mapping of
   ``IssuePoll`` (default: queue ``Raw``).

5. Add ``GitHubIssueRepository`` to the screens where agents should create issues, and the other
   fields to the ticket zoom (*Admin → Dynamic Fields Screens*).

6. Test the poll manually and check the debugger of the web service:

   .. code-block:: bash

      bin/otobo.Console.pl Maint::GenericInterface::TriggerInvoker GitHubConnector IssuePoll

7. Enable the daemon cron task ``Daemon::SchedulerCronTaskManager::Task###GitHubIssuePoll``.
   Its ``Params`` are the name of the web service (default ``GitHubConnector``) and the name of
   the invoker.


Invokers of the Ready2Adopt Web Service
---------------------------------------

=============== ======================== ============================================================
Invoker         Type                     Trigger
=============== ======================== ============================================================
IssuePoll       GitHub::IssuePoll        daemon cron task ``GitHubIssuePoll`` or console command
CommentsGet     GitHub::CommentsGet      scheduled by ``IssuePoll`` for issues with comments
IssueCreate     Ticket::TicketCreate     ``GitHubIssueRepository`` set on a ticket without issue
CommentCreate   Ticket::TicketUpdate     new agent article visible for the customer
IssueClose      Ticket::TicketUpdate     ticket closed, *closed unsuccessful* closes the issue as
                                         *not planned*
=============== ======================== ============================================================

IssueCreate uses the event condition ``GitHubIssueNotCreated``: a condition "field is empty" is
not possible with the condition types *String* and *Regexp*. Without it, changing the repository
of a ticket would create a second issue.

CommentCreate posts only the name of the agent, not the e-mail address.


.. _invoker-issuepoll:

Invoker GitHub::IssuePoll
-------------------------

The outbound mapping builds the query of the GitHub search. Its variables:

``Organization``
    GitHub organization (or user) of the repositories.

``IssueType``, ``Label``
    Only issues of this issue type or with this label, empty for all issues.

``TimeWindow``
    Only issues updated within this period (ISO 8601 duration, default ``-PT15M``). It must be
    longer than the interval of the cron task. Empty: all open issues (initial load).

``Sort``, ``Page``
    Sort field (``updated`` or ``created``) and page of the result (100 issues per page).

The inbound mapping returns a list of ``Issue`` elements:

.. code-block:: perl

   Issue => [
       {
           # finds the ticket of the issue
           MatchDynamicField => { Name => 'GitHubIssueID', Value => 'RotherOSS/otobo#123' },

           # only used if no ticket is found
           SkipCreate   => 0,    # 1: no new ticket, e.g. for issues created by OTOBO
           Ticket       => { Title => '...', Queue => 'Raw', Type => '...', State => 'new', Priority => '3 normal' },
           DynamicField => [ { Name => 'GitHubIssueID', Value => '...' }, ... ],
           Article      => { SenderType => 'customer', IsVisibleForCustomer => 1, From => '...', Subject => '...', Body => '...' },

           # only used for existing tickets, values are only written if they changed
           Update    => { DynamicField => [ { Name => 'GitHubIssueLabels', Value => [ 'bug' ] } ] },
           StateSync => { IsClosed => 1, ClosedState => 'closed successful', OpenState => 'open' },

           # invokers scheduled for the ticket
           FollowUp => [ { Invoker => 'CommentsGet', Data => { Owner => '...', Repo => '...', Number => 123 } } ],
       },
   ],

For every issue:

- No ticket found and the issue is open: the ticket is created with its dynamic fields and the
  first article. Closed issues and issues with ``SkipCreate`` get no ticket.
- Ticket found: the dynamic fields of ``Update`` are written if they changed, and the ticket is
  closed or reopened if the issue was closed or reopened.
- The ``FollowUp`` invokers are scheduled for the ticket.

Dynamic fields
    ``MatchDynamicField`` must be a field that can be searched with *Equals*, e.g. a text field.
    Fields with *Multi value* get a list: the mapping repeats the ``Value`` element, a single
    value or no value is converted to a list.

    Instead of ``Value`` a field can get the ID of a config item (``ConfigItemLookup``), e.g. to
    fill a reference field with the CMDB entry of the repository:

    .. code-block:: perl

       {
           Name             => 'MyConfigItemReference',
           ConfigItemLookup => {
               Class        => 'Software',
               DynamicField => 'MyGitHubRepositoryField',    # or Name => 1 to search the name
               Value        => 'otobo',
               Required     => 1,                            # 1: no ticket without config item
           },
       },

Issue fields
    The search result contains the issue fields of the organization (``issue_field_values``).
    The example mapping takes the field ``Priority`` (Urgent, High, Medium, Low) as ticket
    priority when the ticket is created.

GitHub responses contain keys that are no valid XML names (e.g. the reactions ``+1`` and
``-1``). Every inbound XSLT mapping needs the following pre regex filters, the Ready2Adopt web
service contains them:

========================= =========
Search                    Replace
========================= =========
``[^A-Za-z0-9_.-]``       ``_``
``^([0-9.-])``            ``_$1``
========================= =========


Invoker GitHub::CommentsGet
---------------------------

The inbound mapping returns a list of ``Article`` elements. Articles whose
``MatchDynamicField`` value already exists in an article of the ticket are skipped.

.. code-block:: perl

   Article => [
       {
           MatchDynamicField    => { Name => 'GitHubCommentID', Value => '6544623469' },
           SenderType           => 'customer',
           IsVisibleForCustomer => 1,
           From                 => 'octocat (GitHub)',
           Subject              => '...',
           Body                 => '...',
           DynamicField         => [ { Name => 'GitHubCommentID', Value => '6544623469' } ],
       },
   ],


Initial Load
------------

The search returns at most 100 issues per call and at most 1000 issues in total. To import all
open issues once, before enabling the cron task:

1. Outbound mapping of ``IssuePoll``: ``TimeWindow`` empty, ``Sort`` = ``created``, ``Page`` = ``1``.
2. Run ``Maint::GenericInterface::TriggerInvoker GitHubConnector IssuePoll``.
3. Set ``Page`` to 2, 3, ... and run it again until a page returns no issues
   (``"items":[]`` in the debugger). The number of issues is ``total_count`` in the
   debugger entry *JSON data received from remote system*.
4. Restore ``TimeWindow`` = ``-PT15M``, ``Sort`` = ``updated``, ``Page`` = ``1``.

Existing tickets are only updated, a run too many does no harm. Closed issues are not imported.
For more than 1000 open issues restrict the query, e.g. with ``Label``.


Adapting the Web Service
------------------------

The Ready2Adopt web service is an example. Typical adaptions:

- Process tickets: set ``ProcessManagementProcessID`` and ``ProcessManagementActivityID`` as
  dynamic fields of the new ticket.
- Own dynamic fields: replace the field names in all mappings and in the event conditions.
  For a trigger of ``IssueCreate`` other than ``GitHubIssueRepository``, e.g. a field for the
  publication, use your own event condition.
- Only some repositories: use a ``ConfigItemLookup`` with ``Required`` (only repositories with a
  config item), ``Label`` or ``IssueType``.


System Configuration Settings
-----------------------------

``GenericInterface::Invoker::Module###GitHub::IssuePoll``, ``GenericInterface::Invoker::Module###GitHub::CommentsGet``
    Registration of the invokers.

``Daemon::SchedulerCronTaskManager::Task###GitHubIssuePoll``
    Cron task of the poll, disabled by default.
