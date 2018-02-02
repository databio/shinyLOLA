# Run a LOLAweb Docker Swarm

In order to deploy multiple LOLAweb containers in a high-availability configuration, two elements are required:

1. A **deployment platform** for running multiple containers. Docker Swarm is a common choice for this, as is Kubernetes or Amazon ECS/Fargate. [Install Docker CE](https://docs.docker.com/engine/installation/) (Community Edition). Most server package repositories (i.e. Ubuntu, CentOS) are typically not current enough to run the solution below. Follow the Docker installation documentation carefully to install a current version of the Docker Engine.
2. A **load-balancing mechanism** that distributes user traffic to various containers. For Shiny Server, a load balancer needs to 
support both (a) sticky sessions and (b) websocket connections. Common load-balancing solutions are Nginx, HAproxy, or Apache2. However, to deliver a fully-containerized, performant stack, the [Tr&aelig;fik](https://traefik.io/) load balancer is a perfect choice.

The solution below describes a Docker "Stack" that incorporates these requirements in the form of two services: a swarm of LOLAweb containers and
a load balancer using the Tr&aelig;fik container image. Docker's stack deployment feature is used to launch the stack, which creates and populates all necessary resources. 


![Docker Stack Architecture](https://s3.amazonaws.com/uvasom-resources/publish/docker-lola-complete.png)


The main elements of this stack:

1. Container Services
    - LOLAweb application - the Shiny application itself
    - Tr&aelig;fik load balancer - distributes traffic to containers using sticky sessions and websockets
2. Network definition - creates an overlay network for communication between containers


## Docker Stack Definition

Docker Stack YAML file `docker-compose.yml`:

    version: "3"
    
    services:
     
      app:
        image: somrc/shiny-lola
        networks:
          - net
        ports:
          - "80"
        volumes:
          - /home/lola/reference:/srv/shiny-server/shinyLOLA/reference
          - /home/lola/universes:/srv/shiny-server/shinyLOLA/universes
          - /home/lola/userSets:/srv/shiny-server/shinyLOLA/userSets
          - /home/lola/shinylog:/var/log/shiny-server
        deploy:
          mode: replicated
          replicas: 4
          resources:
            limits:
              memory: 12G
          labels:
            - "traefik.docker.network=lola_net"
            - "traefik.port=80"
            - "traefik.frontend.rule=PathPrefix:/shinyLOLA;"
            - "traefik.backend.loadbalancer.sticky=true"
    
      loadbal:
        image: traefik
        command: --docker \
          --docker.swarmmode \
          --docker.watch \
          --web \
          --loglevel=DEBUG
        ports:
            - 80:80
            - 8080:8080
        volumes:
            - /var/run/docker.sock:/var/run/docker.sock
        deploy:
          mode: replicated
          replicas: 1
          resources:
            limits:
              memory: 10M
        networks:
          - net
    
    networks:
      net:


Take note of a few important elements of this YAML file:

- The `shiny-lola` containers run on an internal overlay network, via port 80.
- Each container mounts four local volumes to read LOLA reference data.
- The swarm runs 4 replicas of the `shiny-lola` container, each capped at 12GB of memory.
- The Shiny containers are labeled with additional information passed to the Tr&aelig;fik load balancer.
- Tr&aelig;fik listens on the overlay network port 80, and is published to the host network over port 80. Port 8080 provides a monitoring interface if so desired.
- One replica of the Tr&aelig;fik load balancer runs in that service, capped at 10MB of memory.
- Tr&aelig;fik mounts and monitors the Docker socket file in order to automatically update anytime the swarm behind it is updated.

## Container Images
Images used in this stack must be downloadable as pre-built images from a container repository such as [Docker Hub](https://hub.docker.com/).
Hand-built local images will fail to deploy unless you push them to a repository (such as Docker Hub) and then pull from there.

Pull the LOLAweb and Tr&aelig;fik container images:

    $ docker pull somrc/shiny-lol
    $ docker pull traefik


To push your own build to Docker Hub:

    $ docker build -t <your-account>/<your-container-name>:tagname .
    $ docker push <your-account>/<your-container-name>:tagname


## Create a Swarm

In order to run this stack, you must first initialize a swarm of one or more computers:

    $ docker swarm init

If running across multiple nodes, the first node to run this command will become a "manager" node. Other nodes in your swarm should join as
"worker" nodes. This status can be helpful for specific placement of some or all containers. As noted using the `placement` tag in `docker-compose.yml`,
you can specify whether containers should run on a manager or worker node. If left unspecified, they will be created evenly across your entire swarm
of host machines.

To inspect nodes in your swarm and their status:

    $ docker node ls
     
    ID                    HOSTNAME               STATUS        AVAILABILITY     MANAGER STATUS
    u9gbc2xxqrzs5ns1n *   host1.virginia.edu     Ready         Active           Leader
    68qie29dsjc88r5c6     host2.virginia.edu     Ready         Active              


## Run the Stack

Once a swarm has been created, issue this command:

    $ docker stack deploy --compose-file docker-compose.yml lola


Point the command-line to the YAML file. The name at the end denotes a prefix name given to elements of your stack. Notice that the label
`"traefik.docker.network=lola_net"` in the app settings must contain this prefix.


## Manage the Stack

### Update the Stack

If you update one of the containers in a stack, and want to push the new image into a swarm, either tear down the entire stack and stop
all containers, or seamlessly inject your revised containers like this:

First, list the services in your stack:

    $ docker service ls

    ID                  NAME                MODE                REPLICAS            IMAGE                     PORTS
    d7lzimlt0ayj        lola_loadbal        replicated          1/1                 traefik:latest            *:80->80/tcp,*:3939->8080/tcp
    572dn5lstoh0        lola_app            replicated          4/4                 somrc/shiny-lola:latest   *:30003->80/tcp


If necessary, inspect the specific service you want to update (by name):

    $ docker service inspect --pretty lola_app


Next, pull the newer container image(s):

    $ docker pull somrc/shiny-lola:latest


Finally, update the service to reference the newest version of the container:

    $ docker service update --image somrc/shiny-lola:latest lola_app


If you change parameters of the `docker-compose.yml` file, just run the `docker stack deploy` command again to refresh:

    $ docker stack deploy --compose-file docker-compose.yml lola


Alternatively, to modify the size of the LOLAweb swarm just update the number of replicas:

    $ docker service update --replicas 10 lola_app


### View Statistics

To watch statistics on your running stack from the console:

    $ docker stats


Tr&aelig;fik also gives a dashboard for containers and their health:

    http://<host-machine>:8080/

![Docker Stack Architecture](https://s3.amazonaws.com/uvasom-resources/publish/traefik-dashboard.png)


### Removing Services

To remove a service:

    $ docker service rm lola_app


## More Information

### Docker
- [Get Started (Overview)](https://docs.docker.com/get-started/)
- [Container Documentation](https://docs.docker.com/get-started/part2/)
- [Compose Documentation](https://docs.docker.com/compose/reference/)
- [Swarm Documentation](https://docs.docker.com/get-started/part4/)
- [Tr&aelig;fik Load Balancer](https://docs.traefik.io/)

This solution is based on the [slopp/Load-Test](https://github.com/slopp/Load-Test/) documentation in GitHub.