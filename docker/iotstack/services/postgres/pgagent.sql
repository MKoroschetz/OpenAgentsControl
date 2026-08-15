-- **** This script must be run with superuser permisson in the DB

-- Create the pgagent role pgagent will use
CREATE ROLE pgagent WITH LOGIN PASSWORD 'your_secure_password';

-- # install Extension
CREATE EXTENSION IF NOT EXISTS pgagent;

-- Grant usage on the schema
GRANT USAGE ON SCHEMA pgagent TO pgagent;

-- Grant access to all tables, sequences, and functions
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA pgagent TO pgagent;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA pgagent TO pgagent;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pgagent TO pgagent;

-- Grant connect privilege on the target database
GRANT CONNECT ON DATABASE yourdb TO pgagent;
