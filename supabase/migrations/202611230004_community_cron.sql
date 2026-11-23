create extension if not exists pg_cron with schema pg_catalog;

grant usage on schema cron to postgres;
grant select, insert, update, delete on cron.job to postgres;

select cron.schedule(
  'koko-weekly-runs-and-arrivals',
  '*/15 * * * *',
  'select koko_private.publish_weekly_runs();'
);
