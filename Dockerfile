FROM ubuntu:18.04
# NOTE - ubuntu is used solely for ease of Dockerfile editing, since more people are familiar with Ubuntu than other distros.
#     A version using an Alpine base would be a good idea for smaller footprint.

# Copy Vulnerable web applications to test
ADD oscommerce-2.3.3/catalog /var/www/html/oscommerce


# Setup local variables. Centrally located for easy config changes.
ENV python=python2.7
ENV DEBIAN_FRONTEND=noninteractive
ENV INSTALL_DIR='/usr/src/'

# Update package list. Necessary to installl literally anything.
RUN apt-get update

# Add necessary repositories
RUN apt-get install -y software-properties-common \
        && apt-get update \
        # Java 8 repository. Main apt repository has nothing older than Java 10.
        && add-apt-repository -y ppa:webupd8team/java \
        # Php 7.0 repository. Main apt repository only has 7.2.
        && add-apt-repository -y ppa:ondrej/php \
        && apt-get update

# Install java 8.
# Warning - Joern requests Java 7 (See  https://joern.readthedocs.io/en/latest/installation.html), however
#    Neo4j 2.1.5 requests Java 8. Java 8 appears to have worked thus far.
RUN echo "oracle-java8-installer shared/accepted-oracle-license-v1-1 select true" | debconf-set-selections \
        && apt-get install -y oracle-java8-installer \
        && java -version

# Install basics. These are all required by various components.
RUN apt-get install -y \
        re2c \
        zip \
        # Just installed for ease of editing if one requires to go into the container.
        vim \
        # Needed for retrieving and installing various components
        git \
        wget \
        # Required by Joern. See https://joern.readthedocs.io/en/latest/installation.html.
        graphviz \
        libgraphviz-dev \
        # Phpjoern and php-ast request php 7.0 in particular. Other components install php 7.2 as well, however no
        #   conflicts between these two have been observed.
        php7.0 \
        php7.0-common \
        php7.0-opcache \
        php7.0-dev \
        # Used in installation of Z3, as one of the files has DOS line endings.
        dos2unix \
        # Various versions of python are used throughout the project. This sets them up in the beginning for ease with the tools
        #    to add libraries and features as necessary.
        python \
        python-pip \
        python3 \
        python3-pip \
        python3-distutils \
        python-setuptools \
        python-dev \
        # Various build tools used by different packages.
        make \
        gradle \
        maven \
        g++ \
        # Used in Z3_Str2.
        g++-4.8 \
        ant

# Install php ast.
# Required by phpjoern. See https://github.com/aalhuz/phpjoern/tree/navex.
ENV PHP_AST="$INSTALL_DIR/php-ast/"
RUN git clone https://github.com/nikic/php-ast $PHP_AST \
        && git -C $PHP_AST checkout tags/v0.1.2 \
        && cd $PHP_AST \
        && phpize \
        && $PHP_AST/configure \
        && make -C $PHP_AST \
        && make -C $PHP_AST install
        # WARNING - Make test fails two tests. Is this an issue? Haven't seen any issues thus far,
        #     so test was simply commented out below.
        #&& make -C $PHP_AST test \
#      Edit php.ini as instructed.
RUN echo "extension=ast.so" >> /etc/php/7.0/cli/php.ini

# Install phpjoern.
ENV PHPJOERN="$INSTALL_DIR/phpjoern/"
RUN git clone https://github.com/aalhuz/phpjoern.git $PHPJOERN
#       Validate this works (or at least doesn't crash).
#RUN $PHPJOERN/php2ast $PHPJOERN/src/util.php
ENV PHPJOERN_HOME="$INSTALL_DIR/phpjoern/"


### Generating code property graphs with Joern
RUN git clone https://github.com/octopus-platform/joern $INSTALL_DIR/joern-octopus \
	&& cd $INSTALL_DIR/joern-octopus  \
	#&& gradle build
	&& sh build.sh -Xlint

# Install Neo4j.
# Required by basically all components. Neo4j forms the attack graph that everything works off of.
RUN wget -O - https://debian.neo4j.org/neotechnology.gpg.key | apt-key add \
        && echo 'deb https://debian.neo4j.org/repo stable/' | tee -a /etc/apt/sources.list.d/neo4j.list \
        && apt-get update \
        # Joern requests version 2.1.5 of Neo4j. See https://joern.readthedocs.io/en/latest/installation.html
        && apt-get install -y neo4j=2.1.5
#      Add neo4j install location to path. This is necessary so other programs can interact with the server.
ENV NEO4J_HOME="/var/lib/neo4j/"
ENV PATH="${NEO4J_HOME}/bin/:${PATH}"

# Get batch importer.
# Required by phpjoern. See https://github.com/aalhuz/phpjoern/tree/navex.

RUN git clone https://github.com/jexp/batch-import.git $INSTALL_DIR/batch-import \
	&& cd $INSTALL_DIR/batch-import \
	&& git checkout 2.1
ENV JEXP_HOME="$INSTALL_DIR/batch-import/"

# Gremlin for Neo4j.
# Required by Joern. See https://joern.readthedocs.io/en/latest/installation.html
# WARNING - Currently this just compiles the master branch. Joern demands Gremlin for 2.X, which master currently is.
#     In the future, a specific version may need to be checked out to be funcitonal.
ENV GREMLIN='/usr/src/gremlin/'
RUN git clone https://github.com/neo4j-contrib/gremlin-plugin.git $GREMLIN \
        # Build while skipping license verification. If you don't specify to skip the license, it throws an error and cancels the build.
        && mvn clean package -f $GREMLIN/pom.xml -Dlicense.skip=true \
        && unzip $GREMLIN/target/neo4j-gremlin-plugin-2.1-SNAPSHOT-server-plugin.zip -d $NEO4J_HOME/plugins/gremlin-plugin \
        && cd $NEO4J_HOME \
        # neo4j needs to be started so we can use it later. `neo4j start` appears to time out with this version of neo4j, but
        # specifying to start without a wait has worked consistently thus far.
        && bin/neo4j start-no-wait


# Joern from aalhuz fork
ENV JOERN="$INSTALL_DIR/joern/"
RUN git clone https://github.com/aalhuz/joern.git $JOERN  
	#&& cd $JOERN \
	#&& gradle build


# Joern Tools.
ENV JOERN_TOOLS="$INSTALL_DIR/joern-tools/"f24a2cec9d5b
# Requires an up to date version of crypto library.
RUN pip2 install cryptography -U \
        && git clone https://github.com/fabsx00/joern-tools $JOERN_TOOLS \
        && python2 $JOERN_TOOLS/setup.py install

# Python Joern.
# Used for graph traversal w/ attack dictionary.
# See https://github.com/aalhuz/python-joern/tree/navex
# Calls for this version of py2neo. See location specified above.
ENV PYTHONJOERN="$INSTALL_DIR/pythonjoern/"
RUN git clone https://github.com/aalhuz/python-joern.git $PYTHONJOERN
RUN pip2 install py2neo==2.0.7 \
        && pip2 install git+git://github.com/fabsx00/python-joern.git \
	&& cd $PYTHONJOERN \
	&& mkdir results \
	&& touch results/static_analysis_results.txt \
	&& touch results/include_map_results.txt \
	&& touch results/static_analysis_results_code.txt \
	&& touch results/static_analysis_results_os-command.txt \
	&& touch results/static_analysis_results_file-inc.txt \
	&& touch results/static_analysis_results_ear.txt \
	




# XDebug 2.5.2.
# Required for exploit generation. 2.5.2 request in documentation.
# See https://github.com/aalhuz/navex
ENV XDEBUG="$INSTALL_DIR/xdebug/"
RUN git clone https://github.com/xdebug/xdebug.git $XDEBUG \
        && git -C $XDEBUG checkout tags/XDEBUG_2_5_2 \
        # Turn off all warnings are errors. Doesn't build otherwise.
        && sed -i 's/-Werror//g' $XDEBUG/rebuild.sh \
        && cd $XDEBUG \
        && $XDEBUG/rebuild.sh

# Z3.
# Install z3str2, the version used by this program.
# See https://github.com/z3str/Z3-str/blob/master/README_OLD.md.
#	Get z3 4.1.1.
ENV Z3_DIR="$INSTALL_DIR/z3"
ENV Z3STR_DIR="$INSTALL_DIR/z3_str2"
RUN git clone https://github.com/Z3Prover/z3.git $Z3_DIR \
    && cd $Z3_DIR \
    && git checkout tags/z3-4.1.1
#	Get z3 str 2
RUN git clone https://github.com/z3str/Z3-str.git $Z3STR_DIR
#	patch z3 and build.
RUN cp $Z3STR_DIR/z3.patch $Z3_DIR/ \
    && cd $Z3_DIR \
    && dos2unix z3.patch \
    && patch -p0 < z3.patch \
    && autoconf \
    && ./configure \
    && make CPP=g++-4.8 CXX=g++-4.8 \
    && make a CPP=g++-4.8 CXX=g++-4.8
#	build z3str2
RUN cd $Z3STR_DIR \
    && make Z3_path=$Z3_DIR \
    # Have to manually specify the location of z3str2 in this file. See https://github.com/z3str/Z3-str/blob/master/README_OLD.md
    && sed -i 's#solver = ""#solver = "./str"#g' Z3-str.py

# Install necessary version of autoconf.
# Required by SpiderMonkey 1.8.5 . See https://developer.mozilla.org/en-US/docs/Mozilla/Projects/SpiderMonkey/Build_Documentation.
ENV AUTOCONF="$INSTALL_DIR/autoconf-2.13/"
RUN wget -P $INSTALL_DIR https://launchpad.net/ubuntu/+archive/primary/+sourcefiles/autoconf2.13/2.13-62/autoconf2.13_2.13.orig.tar.gz \
        && tar -xzv -C $INSTALL_DIR -f $INSTALL_DIR/autoconf2.13_2.13.orig.tar.gz \
        # Removing compressed file for cleanliness.
        && rm $INSTALL_DIR/autoconf2.13_2.13.orig.tar.gz \
        && cd $AUTOCONF \
        && ./configure \
        && make \
        && make check \
        && make install \
        # We want autoconf 2.13 to be accessible as a command, but it is clobbered by the new autoconf in /usr/bin.
        # Create a copy in our local with a new name and hash it so it is accessible.
        && mv /usr/local/bin/autoconf /usr/local/bin/autoconf-2.13 \
        && hash /usr/local/bin/autoconf-2.13

# Spidermonkey 1.8.5
# Required for exploit generation.
# See https://github.com/aalhuz/navex and https://developer.mozilla.org/en-US/docs/Mozilla/Projects/SpiderMonkey/Build_Documentation.
# NOTE - I didn't follow the all caps convention for this variable as the documentation says to store the location in a environment variable
#         named `SpiderMonkey`. It is unclear if this is referenced by name in the program, so this name was used just in case.
ENV SpiderMonkey="$INSTALL_DIR/js-1.8.5/"
RUN wget -P $INSTALL_DIR http://ftp.mozilla.org/pub/mozilla.org/js/js185-1.0.0.tar.gz \
        && tar -xzv -C $INSTALL_DIR/ -f $INSTALL_DIR/js185-1.0.0.tar.gz \
        # Removing the compressed file for cleanliness.
        && rm $INSTALL_DIR/js185-1.0.0.tar.gz \
        && cd $SpiderMonkey/js/src \
        && autoconf-2.13 \
        # This name should end with "_OPT.OBJ" to make the version control system ignore it.
        && mkdir build_OPT.OBJ \
        && cd build_OPT.OBJ \
        && ../configure
        # ERROR - running make on this creates an error regarding implicit type conversion from boolean to a javascript array. Haven't been
        #     able to locate any documentation on how to fix without editing the code.
        #&& make

# Narcissus fork.
# Required by Navex run.pl for application crawling of JS.
# See https://github.com/aalhuz/navex at bottom of README.
# NOTE - There are no build instructions that I can find, so I am assuming this is just interpreted as is.
ENV NARCISSUS="$SpiderMonkey/js/narcissus"
RUN git clone https://github.com/aalhuz/narcissus.git $NARCISSUS

# crawler4j.
# Required by Navex run.pl for crawling web apps.
# See https://github.com/aalhuz/crawler4j
# TODO - It isn't clear how to build this script from the README and thus it hasn't been done yet! Maven throws
#      an error that there is no stated goal. Requires more looking into.
ENV CRAWLER4J="$INSTALL_DIR/crawler4j"
RUN git clone https://github.com/aalhuz/crawler4j.git $CRAWLER4J

# Navex itself (Finally!).
# Used for application crawling. See https://github.com/aalhuz/navex at bottom of README.
ENV NAVEX="$INSTALL_DIR/navex"
RUN git clone https://github.com/aalhuz/navex.git $NAVEX




