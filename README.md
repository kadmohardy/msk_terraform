### Create topic

./kafka-topics.sh --bootstrap-server b-2.mymsk.j85bma.c22.kafka.us-east-1.amazonaws.com:9092 --create --topic accounts-topic --partitions 1 --replication-factor 1

### List topics
./kafka-topics.sh --list --bootstrap-server b-2.mymsk.j85bma.c22.kafka.us-east-1.amazonaws.com:9092

### Produce to topic 
./kafka-console-producer.sh --bootstrap-server b-2.mymsk.j85bma.c22.kafka.us-east-1.amazonaws.com:9092 --topic accounts-topic 

### List consumer groups
./kafka-consumer-groups.sh --bootstrap-server b-2.mymsk.j85bma.c22.kafka.us-east-1.amazonaws.com:9092  --list

### Delete topic
./kafka-topics.sh --bootstrap-server b-2.mymsk.j85bma.c22.kafka.us-east-1.amazonaws.com:9092 --delete --topic accounts-topic

### Describe topic
./kafka-topics.sh --bootstrap-server b-2.mymsk.j85bma.c22.kafka.us-east-1.amazonaws.com:9092 --describe -topic accounts-topic

### Consume from topic

./kafka-console-consumer.sh --bootstrap-server b-2.mymsk.j85bma.c22.kafka.us-east-1.amazonaws.com:9092 --topic accounts-topic --from-beginning