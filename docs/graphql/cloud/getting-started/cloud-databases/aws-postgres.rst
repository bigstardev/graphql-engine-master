.. meta::
   :description: Using Hasura with an AWS RDS Postgres database
   :keywords: hasura, docs, existing database, guide, aws rds postgres

.. _cloud_db_aws_rds_postgres:

Using Hasura Cloud with an AWS RDS Postgres database
====================================================

.. contents:: Table of contents
  :backlinks: none
  :depth: 2
  :local:

Introduction
------------

This guide explains how to connect a new or existing AWS RDS Postgres database to a Hasura Cloud project.

Step 0: Sign up or log in to Hasura Cloud
-----------------------------------------

Navigate to `Hasura Cloud <https://cloud.hasura.io/signup/?pg=docs&plcmt=body&cta=navigate-to-hasura-cloud&tech=default>`__ and sign up or log in.

.. _create_hasura_project_aws_rds_postgres:

Step 1: Create a Hasura Cloud project
-------------------------------------

On the Hasura Cloud dashboard, create a new project:

.. thumbnail:: /img/graphql/cloud/cloud-dbs/create-hasura-cloud-project.png
   :alt: Create Hasura Cloud project
   :width: 1000px

After the project is initialized successfully, click on ``Launch console`` to open the Hasura console in your browser.

On the Hasura console, navigate to ``Data -> Manage -> Connect Database -> Connect existing database``:

You will get prompted for a Postgres Database URL. We will create this in the next step and then come back here.

.. thumbnail:: /img/graphql/cloud/cloud-dbs/existing-db-setup.png
   :alt: Hasura Cloud database setup
   :width: 700px

.. _create_aws_rds_postgres_db:

Step 2: Create a Postgres DB on AWS (skip if you have an existing DB)
---------------------------------------------------------------------

Log into the `AWS console <https://console.aws.amazon.com//>`__.

On the top left, click on ``Services`` and type "RDS" into the search field. Then click on ``RDS``:

.. thumbnail:: /img/graphql/cloud/cloud-dbs/aws/search-for-rds.png
   :alt: Navigate to RDS in AWS
   :width: 1000px

Click the ``Create database`` button:

.. thumbnail:: /img/graphql/cloud/cloud-dbs/aws/create-database.png
   :alt: Create database in AWS
   :width: 1000px

In ``Engine options``, select ``Postgres`` as ``Engine type``:

.. thumbnail:: /img/graphql/cloud/cloud-dbs/aws/postgres/rds-select-postgres.png
   :alt: Select Postgres for RDS instance on AWS
   :width: 600px

Scroll down to ``Settings``. Now you can choose a ``DB instance identifier`` as a name for your database. The ``Master username`` is ``postgres`` by default. 
You can change that if you have to. As for the password, you can click the checkbox for AWS to auto-generate one for you, or you can type in a password of your choice.

.. thumbnail:: /img/graphql/cloud/cloud-dbs/aws/rds-settings.png
   :alt: Settings for RDS instance on AWS
   :width: 600px

Scroll down and customize other database options such as ``DB instance size`` and ``Storage``, based on your requirements.

In the ``Connectivity`` section, expand the ``Additional connectivity configuration``. Then set ``Public access`` to ``Yes`` and choose or add a new security group:

.. thumbnail:: /img/graphql/cloud/cloud-dbs/aws/rds-connectivity.png
   :alt: Connectivity for RDS instance on AWS
   :width: 600px

When you're done, at the bottom, click the ``Create database`` button:

.. thumbnail:: /img/graphql/cloud/cloud-dbs/aws/rds-click-create.png
   :alt: Create RDS instance on AWS
   :width: 700px

.. note::

   If you're using a database user other than the default one, make sure to give it the right :ref:`Postgres permissions <cloud_postgres_permissions>`.

Step 3: Allow connections to your DB from Hasura Cloud
------------------------------------------------------

On the database dashboard, click on ``Connectivity & security``. On the right, click on the security group that you selected or added in :ref:`step 2 <create_aws_rds_postgres_db>`.

.. thumbnail:: /img/graphql/cloud/cloud-dbs/aws/postgres/find-security-group.png
   :alt: Find the security group on AWS RDS
   :width: 1000px

Click on the security group:

.. thumbnail:: /img/graphql/cloud/cloud-dbs/aws/select-security-group.png
   :alt: Click on the security group
   :width: 1000px

Click on ``Edit inbound rules``:

.. thumbnail:: /img/graphql/cloud/cloud-dbs/aws/inbound-rules.png
   :alt: Edit inbound rules for AWS RDS database
   :width: 1000px

Click on ``Add rule``:

.. thumbnail:: /img/graphql/cloud/cloud-dbs/aws/add-inbound-rule.png
   :alt: Add an inbound rule for AWS RDS database
   :width: 1000px

Copy the IP address from the copy icon in the ``Hasura Cloud IP`` field on the project's details view on Hasura Cloud.

.. thumbnail:: /img/graphql/cloud/projects/hasura-cloud-ip.png
   :alt: Hasura Cloud IP field
   :width: 1000px

Add the Hasura IP address that you copied:

.. thumbnail:: /img/graphql/cloud/cloud-dbs/aws/add-hasura-ip.png
   :alt: Add the Hasura IP for AWS RDS database
   :width: 1000px

Then click ``Save rules``.

.. _construct_db_url_aws_postgres:

Step 4: Construct the database connection URL
---------------------------------------------

The structure of the database connection URL looks as follows:

.. code-block:: bash

    postgresql://<user-name>:<password>@<public-ip>:<postgres-port>/<db>

On the database dashboard, click on ``Connectivity & security``:

.. thumbnail:: /img/graphql/cloud/cloud-dbs/aws/postgres/get-db-connection-string.png
   :alt: Construct the database connection string for AWS RDS
   :width: 1000px

- ``user-name``: If you have a separate database user the user name will be their name. If you didn't specify a user, the default user name is ``postgres``.
- ``password``: If you have a separate database user, use their password. Otherwise, use the password that you chose when creating the database.
- ``public-ip``: On the screenshot above, the ``Endpoint`` is the public IP.
- ``postgres-port``: On the screenshot above you can find it under ``Port``. The default port for Postgres is ``5432``.
- ``db``: The DB is ``postgres`` by default unless otherwise specified.

Step 5: Finish connecting the database
--------------------------------------

Back on Hasura Console, enter the database URL that we retrieved in :ref:`step 4 <construct_db_url_aws_postgres>`:

.. thumbnail:: /img/graphql/cloud/getting-started/connect-db.png
   :alt: Database setup
   :width: 600px

Then click ``Connect Database``.

.. note::

   For security reasons, it is recommended to set database URLs as :ref:`env vars <manage_project_env_vars>` and using the env vars
   to connect to the databases in place of the raw database URLs.

Voil??. You are ready to start developing.

.. thumbnail:: /img/graphql/cloud/cloud-dbs/hasura-console.png
   :alt: Hasura console
   :width: 1100px

Next steps
----------

You can check out our `30-Minute Hasura Basics Course <https://hasura.io/learn/graphql/hasura/introduction/>`__
and other `GraphQL & Hasura Courses <https://hasura.io/learn/>`__ for a more detailed introduction to Hasura.

You can also click the gear icon to manage your Hasura Cloud project. (e.g. add :ref:`collaborators <manage_project_collaborators>`,
:ref:`env vars <manage_project_env_vars>` or :ref:`custom domains <manage_project_domains>`) and :ref:`add an admin secret <secure_project>`
to make sure that your GraphQL endpoint and the Hasura console are not publicly accessible.

.. thumbnail:: /img/graphql/cloud/getting-started/project-manage.png
  :alt: Project actions
  :width: 860px
