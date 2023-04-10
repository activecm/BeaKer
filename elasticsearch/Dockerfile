ARG ELK_STACK_VERSION

FROM docker.elastic.co/elasticsearch/elasticsearch:${ELK_STACK_VERSION}
ADD ./elasticsearch.yml /usr/share/elasticsearch/config/elasticsearch.yml
RUN mkdir /usr/share/elasticsearch/snapshots
RUN chown elasticsearch:root /usr/share/elasticsearch/snapshots

