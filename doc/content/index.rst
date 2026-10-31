WebService-GitHub
=================

Generic interface invokers to import GitHub issues and their comments as tickets and articles.
The other direction (create issues, post comments, close issues) needs no package, it is done
with the standard invokers ``Ticket::TicketCreate`` and ``Ticket::TicketUpdate``.

The invokers contain no configuration. Queue, type, dynamic fields, process etc. are defined
by the inbound XSLT mapping of the web service, which converts the GitHub response into a
simple structure that the invoker executes.


Invokers
--------

``GitHub::IssuePoll``
    Polls issues, e.g. with ``GET /search/issues``. The outbound mapping builds the query
    (organization, label, time window). For every issue of the inbound mapping:

    - no ticket found (``MatchDynamicField``) and the issue is open: the ticket is created with
      its dynamic fields and the first article,
    - ticket found: the ticket is closed or reopened if the issue was closed or reopened
      (``StateSync``),
    - the ``FollowUp`` invokers are scheduled for the ticket, e.g. ``CommentsGet``.

``GitHub::CommentsGet``
    Imports the comments of an issue, e.g. with
    ``GET /repos/:Owner/:Repo/issues/:Number/comments``. Comments whose ``MatchDynamicField``
    value already exists in an article of the ticket are skipped, so every comment is
    imported only once.

Dynamic fields can get the ID of a config item instead of a value (``ConfigItemLookup``), e.g.
to fill a reference field with the CMDB entry of the repository. With ``Required`` the issue is
skipped if no config item is found. The structures are described in the POD of the modules
``Kernel::GenericInterface::Invoker::GitHub::*``.


Setup
-----

1. Create a web service with the REST transport for ``https://api.github.com`` and add the
   headers ``Authorization: Bearer <token>``, ``Accept: application/vnd.github+json`` and
   ``X-GitHub-Api-Version: 2022-11-28``. The token needs read access to issues.
2. Add the invokers with their XSLT mappings.
3. GitHub responses contain keys that are no valid XML names (e.g. the reactions ``+1`` and
   ``-1``). Add the following pre regex filters to every inbound XSLT mapping:

   ========================= =========
   Search                    Replace
   ========================= =========
   ``[^A-Za-z0-9_.-]``       ``_``
   ``^([0-9.-])``            ``_$1``
   ========================= =========

4. Enable the daemon cron task ``Daemon::SchedulerCronTaskManager::Task###GitHubIssuePoll``
   and set the name of the web service and of the invoker in ``Params``.

The poll can also be run manually:

.. code-block:: bash

   bin/otobo.Console.pl Maint::GenericInterface::TriggerInvoker <web service> IssuePoll


Notes
-----

- The search returns at most 100 issues per call. For an initial load of more issues run the
  poll several times with different time windows or labels.
- Issues and comments created with the token of the web service (e.g. by the standard invokers)
  should be skipped in the inbound mappings, otherwise they are imported again.
