ARG ELK_STACK_VERSION

FROM docker.elastic.co/elasticsearch/elasticsearch:${ELK_STACK_VERSION}
ADD ./elasticsearch.yml /usr/share/elasticsearch/config/elasticsearch.yml
RUN mkdir /usr/share/elasticsearch/snapshots
# The elasticsearch container runs under the elasticsearch user
# Make sure that the elasticsearch user has permission to read/save snapshots
# (this matches the ownership of many other folders within the container)
RUN chown elasticsearch:root /usr/share/elasticsearch/snapshots
# Ensure write permissions for the snapshots directory
RUN chmod -R 775 /usr/share/elasticsearch/snapshots

