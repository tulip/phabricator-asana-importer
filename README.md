phabricator-asana-importer
====================

Script to import Asana tasks into Phabricator.


Prerequisites
====================

- Ruby

- A JSON export of an Asana project. You can get this from the Asana website by
  selecting the project, clicking the arrow next to the project name above the
  tasks, and then selecting "Export → JSON". If you want to import comments,
  you'll need to ask Asana to aso export stories. You can do this with a small
  modification to the URL that Asana redirects you to when you ask for a JSON
  export. Asana will send you to
  `https://app.asana.com/api/1.0/projects/SOME-ID/tasks?opt_pretty&opt_expand=(this%7Csubtasks%2B)`;
  just modify the `opt_expand` parameter in the URL to read `(this%7Cstories%7Csubtasks%2B)`.

- A properly configured `arc` and an `.arcrc` in your home directory. See the
  [Phabricator docs](https://secure.phabricator.com/book/phabricator/article/arcanist/).


Usage
====================

- Clone this repo

- Create a Bot user in Phabricator (https://yourphabricator.com/people/new/bot/)
  and get a conduit token for it (People → your bot user → Edit Settings →
  Conduit API tokens → Generate API Token). You can test that the API token
  (as well as your `arc` installation) works by running
  `echo '{}' | arc call-conduit --conduit-token YOUR-TOKEN user.query`
  which should print details on every user in Phabricator.

- Run `./importer.rb your-export.json your-conduit-token` to run the import.


Notes
====================

Users are matched based on real name. If you'd like to change the matching
logic, see `get_users` and `match_user` in `import.rb`.

Asana sub-tasks are imported as Phabricator separate tasks with the parent
task's name prepended to the sub-task's name. To change this behavior,
see `create_subtask` in `import.rb`. Unfortunately, the Phabricator API does
not allow us to mark these sub-tasks as blocking tasks.


Get Involved
====================

If you've found a bug or have a feature request, [file an issue on Github](https://github.com/tulip/phabricator-asana-importer).


Contributing
====================

How to submit changes:

1. Fork this repository.
2. Make your changes.
3. Email us at opensource@tulip.co to sign a CLA.
4. Submit a pull request.


Who's Behind It
====================

phabricator-asana-importer is maintained by Tulip. We're an MIT startup located in Boston, helping enterprises manage, understand, and improve their manufacturing operations. We bring our customers modern web-native user experiences to the challenging world of manufacturing, currently dominated by ancient enterprise IT technology. We work on Meteor web apps, embedded software, computer vision, and anything else we can use to introduce digital transformation to the world of manufacturing. If these sound like interesting problems to you, [we should talk](mailto:jobs@tulip.co).


License
====================

phabricator-asana-importer is licensed under the [Apache Public License](LICENSE).
