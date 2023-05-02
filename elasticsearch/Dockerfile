ARG ELK_STACK_VERSION

FROM docker.elastic.co/elasticsearch/elasticsearch:${ELK_STACK_VERSION}
ADD ./elasticsearch.yml /usr/share/elasticsearch/config/elasticsearch.yml
RUN mkdir /usr/share/elasticsearch/snapshots
# The elasticsearch container runs under the elasticsearch user
# Make sure that the elasticsearch user has permission to read/save snapshots
# Since this directory is a bind mount, give all users read/write permissions
# in order to avoid flaky write permissions when creating snapshots
RUN chmod -R 777 /usr/share/elasticsearch/snapshots

