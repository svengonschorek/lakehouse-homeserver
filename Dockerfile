FROM python:3.10-bullseye AS spark-base

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      systemctl \
      sudo \
      curl \
      vim \
      unzip \
      rsync \
      openjdk-11-jdk \
      build-essential \
      software-properties-common && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

## Download spark and hadoop dependencies and install

# ENV variables
ENV SPARK_HOME=${SPARK_HOME:-"/opt/spark"}
ENV HADOOP_HOME=${HADOOP_HOME:-"/opt/hadoop"}
ENV SPARK_VERSION=3.5.6
ENV PYTHONPATH=$SPARK_HOME/python/

ENV PATH="/opt/spark/sbin:/opt/spark/bin:${PATH}"
ENV SPARK_MASTER="spark://spark-master:7077"
ENV SPARK_MASTER_HOST=spark-master
ENV SPARK_MASTER_PORT=7077
ENV PYSPARK_PYTHON=python3

# Add iceberg spark runtime jar to IJava classpath
ENV IJAVA_CLASSPATH=/opt/spark/jars/*

RUN mkdir -p ${HADOOP_HOME} && mkdir -p ${SPARK_HOME}
WORKDIR ${SPARK_HOME}

# Download spark
RUN mkdir -p ${SPARK_HOME} \
    && curl -L https://dlcdn.apache.org/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop3.tgz -o spark-${SPARK_VERSION}-bin-hadoop3.tgz \
    && tar xvzf spark-${SPARK_VERSION}-bin-hadoop3.tgz --directory /opt/spark --strip-components 1 \
    && rm -rf spark-${SPARK_VERSION}-bin-hadoop3.tgz

FROM spark-base AS pyspark

# Install python deps
COPY requirements.txt .
RUN pip3 install -r requirements.txt

COPY ./config/spark-defaults.conf "$SPARK_HOME/conf"

RUN chmod u+x /opt/spark/sbin/* && \
    chmod u+x /opt/spark/bin/*

FROM pyspark

# AWS SDK jars
RUN curl https://repo1.maven.org/maven2/software/amazon/awssdk/s3/2.20.148/s3-2.20.148.jar -Lo /opt/spark/jars/s3-2.20.148.jar 
RUN curl https://repo1.maven.org/maven2/software/amazon/awssdk/bundle/2.20.148/bundle-2.20.148.jar -Lo /opt/spark/jars/bundle-2.20.148.jar

# Download iceberg spark runtime
RUN curl https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-spark-runtime-3.5_2.12/1.4.3/iceberg-spark-runtime-3.5_2.12-1.4.3.jar -Lo /opt/spark/jars/iceberg-spark-runtime-3.5_2.12-1.4.3.jar
RUN curl https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-spark-extensions-3.5_2.12/1.4.3/iceberg-spark-extensions-3.5_2.12-1.4.3.jar -Lo /opt/spark/jars/iceberg-spark-extensions-3.5_2.12-1.4.3.jar
RUN curl https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-aws/1.4.3/iceberg-aws-1.4.3.jar -Lo /opt/spark/jars/iceberg-aws-1.4.3.jar

# Download delta jars
RUN curl https://repo1.maven.org/maven2/io/delta/delta-core_2.12/2.4.0/delta-core_2.12-2.4.0.jar -Lo /opt/spark/jars/delta-core_2.12-2.4.0.jar
RUN curl https://repo1.maven.org/maven2/io/delta/delta-spark_2.12/3.2.0/delta-spark_2.12-3.2.0.jar -Lo /opt/spark/jars/delta-spark_2.12-3.2.0.jar
RUN curl https://repo1.maven.org/maven2/io/delta/delta-storage/3.2.0/delta-storage-3.2.0.jar -Lo /opt/spark/jars/delta-storage-3.2.0.jar

# Download hudi jars
RUN curl https://repo1.maven.org/maven2/org/apache/hudi/hudi-spark3-bundle_2.12/0.15.0/hudi-spark3-bundle_2.12-0.15.0.jar -Lo /opt/spark/jars/hudi-spark3-bundle_2.12-0.15.0.jar

# Download hadoop s3 jars
RUN curl https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-aws/3.3.4/hadoop-aws-3.3.4.jar -Lo /opt/spark/jars/hadoop-aws-3.3.4.jar
RUN curl https://repo1.maven.org/maven2/com/amazonaws/aws-java-sdk-bundle/1.12.648/aws-java-sdk-bundle-1.12.648.jar -Lo /opt/spark/jars/aws-java-sdk-bundle-1.12.648.jar

# Download REST catalog jars
RUN curl https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-rest-client/1.4.3/iceberg-rest-client-1.4.3.jar -Lo /opt/spark/jars/iceberg-rest-client-1.4.3.jar

COPY entrypoint.sh .
RUN chmod u+x /opt/spark/entrypoint.sh
