********
Overview
********

Summary
-------

This documentation is an overview of the functionality of the OTOBO package “WebService-GitHub”.

The package connects OTOBO with the issues of GitHub repositories:

- New GitHub issues become tickets, comments on GitHub become articles.
- Closing or reopening an issue on GitHub closes or reopens the ticket.
- The labels of an issue are shown in the ticket and kept up to date.
- An agent creates a GitHub issue for a ticket by entering the repository.
- Articles of agents that are visible for the customer are posted as comments on GitHub.
- Closing the ticket closes the GitHub issue.

GitHub is polled periodically by a daemon cron task, no web hook and no public access to
OTOBO is needed.

Components
----------

``GitHub::IssuePoll`` (invoker)
    Polls the issues of an organization with the GitHub search (``GET /search/issues``).
    For every issue the ticket is created or updated, see :ref:`invoker-issuepoll`.

``GitHub::CommentsGet`` (invoker)
    Imports the comments of an issue as articles. Every comment is imported only once.
    It is scheduled by ``GitHub::IssuePoll`` for issues with comments.

``Kernel::GenericInterface::Event::Validation::GitHubIssueNotCreated`` (event condition)
    Condition of type ``Module`` for invoker events. It matches if the ticket has no GitHub
    issue yet, so that only one issue is created per ticket.

Ready2Adopt web service ``GitHubConnector``
    A complete web service with all invokers and mappings. Its import creates the needed
    dynamic fields, see :ref:`ready2adopt-web-service`.

Daemon cron task ``GitHubIssuePoll``
    Runs the invoker ``IssuePoll`` every 5 minutes. It is disabled after the installation.

The other direction (create issues, post comments, close issues) uses the standard invokers
``Ticket::TicketCreate`` and ``Ticket::TicketUpdate`` of OTOBO.

How it works
------------

The invokers contain no configuration. Queue, type, state, priority, dynamic fields, process
etc. of the tickets are defined completely by the inbound XSLT mapping of the web service. The
mapping converts the response of GitHub into a simple structure, which the invoker executes.
This way the web service can be adapted to every ticket setup, e.g. to a process, without
changing the package.

Tickets and articles are found again by a dynamic field with the ID of the issue or the comment
(``MatchDynamicField``). Values are only written if they changed, so a poll without changes
creates no history entries and no events.
