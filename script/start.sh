#!/bin/bash

#Increment count of container restarts
FILE=$(dirname $0)/liferay_runs
if [ -e "$FILE" ]; then
	LIFERAY_RUN=$(cat $FILE)
fi
LIFERAY_RUN=$((LIFERAY_RUN + 1))
echo $LIFERAY_RUN > $FILE

#Stops ssh daemon
service ssh stop

#On first run only, if LIFERAY_NOWIZARD is not set, removes wizard properties file (enable wizard)
if [ $LIFERAY_RUN -eq 1 ]; then
	if [ $LIFERAY_NOWIZARD -ne 1 ]; then
		rm -f ${LIFERAY_HOME}/portal-setup-wizard.properties
	else
		#Sets "liferay.home" wizard property
		echo "liferay.home=$LIFERAY_HOME" >> ${LIFERAY_HOME}/portal-setup-wizard.properties
	fi
	
	#Localhost certificate creation with openssl
	#mkdir -p /var/cert/localhost
	#openssl req -x509 -out /var/cert/localhost/localhost.crt -keyout /var/cert/localhost/localhost.key -newkey rsa:2048 -nodes -sha256 -subj '/CN=localhost' -extensions EXT -config <(printf "[dn]\nCN=localhost\n[req]\ndistinguished_name = dn\n[EXT]\nsubjectAltName=DNS:localhost\nkeyUsage=digitalSignature\nextendedKeyUsage=serverAuth")
	
	#Certbot usage for requesting Let's Encrypt certificate (https://certbot.eff.org/lets-encrypt/ubuntuxenial-other)
	#certbot certonly --webroot -w ${TOMCAT_HOME}/webapps/ROOT -d $VM_HOST
	
	#Generates untrusted local certificate
	$JAVA_HOME/bin/keytool -genkey -alias tomcat -keyalg RSA -storepass changeit -keypass changeit -dname "CN=CT, OU=Dev, O=CtLiv, L=LI, ST=LI, C=IT"	
	#Converts keystore to PKCS12 (open) format
	$JAVA_HOME/bin/keytool -importkeystore -srckeystore /root/.keystore -destkeystore /root/.keystore -srcstorepass changeit -deststorepass changeit -deststoretype pkcs12
fi

if [ $LIFERAY_DEBUG -eq 1 ]; then
	#Configure and launch ssh
	sed -i 's/PermitRootLogin .*/PermitRootLogin yes/' /etc/ssh/sshd_config
	sed -i 's/PubkeyAuthentication yes/PubkeyAuthentication no/' /etc/ssh/sshd_config
	# SSH login fix. Otherwise user is kicked off after login
	sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd	
	#Start ssh daemon
	service ssh start
	
	#Define default host for JMX debugging 
	if [ -z "$VM_HOST" ]; then 
	  VM_HOST=localhost
	fi
	
	## (disabled) Runs jstatd endpoint on port 1098 for remote JVM monitoring (use SSH tunnel)
	## Creates policy file
	#policy=$(dirname $0)/jstatd.all.policy
	#echo "grant codebase \"file:${JAVA_HOME}/lib/tools.jar\" {" > $policy
	#echo "  permission java.security.AllPermission;" >> $policy
	#echo "};" >> $policy	
	## Launch jstatd
	#jstatd -p 1098 -J-Djava.security.policy=$(dirname $0)/jstatd.all.policy -J-Djava.net.preferIPv4Stack=true -J-Djava.rmi.server.hostname=${VM_HOST} &
	
	#Enables JMX endpoint (on port 1099)
	OPTS="-Dcom.sun.management.jmxremote=true"
	OPTS="$OPTS -Dcom.sun.management.jmxremote.ssl=false"
	OPTS="$OPTS -Dcom.sun.management.jmxremote.authenticate=false"
	OPTS="$OPTS -Dcom.sun.management.jmxremote.port=1099"
	OPTS="$OPTS -Dcom.sun.management.jmxremote.rmi.port=1099"
	OPTS="$OPTS -Djava.rmi.server.hostname=${VM_HOST}"

	#Enables jpda remote debugging (same as "export JPDA_ADDRESS=8999 && export JPDA_TRANSPORT=dt_socket && ${TOMCAT_HOME}/bin/catalina.sh jpda run")
	OPTS="$OPTS -Xdebug -agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=8999 "
	#Alternative
	#OPTS="$OPTS -Xdebug --Xrunjdwp:server=y,transport=dt_socket,address=8999,suspend=n "

	#Exports configuration
	export CATALINA_OPTS="$CATALINA_OPTS $OPTS"
fi

#Enables custom jvm options 
if [ -z "$JAVA_OPTS" ]; then 
	echo
	echo "No custom jvm startup options in docker run command"
	echo
else
	export CATALINA_OPTS="$CATALINA_OPTS $JAVA_OPTS"
fi
	
echo "Starting catalina with options: $CATALINA_OPTS"
echo
	
#Launch catalina
${TOMCAT_HOME}/bin/catalina.sh run
