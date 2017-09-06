#!/bin/sh
HOST=$(hostname)
PROG="${0##*/}"
DO_RETURN=${SHLVL}

#DBG="echo"
##########################

echo "using CAPASS as provided"
PASSIN=${CAPASS:+-passin pass:"$CAPASS"}
PASSOUT=${CAPASS:+-passout pass:"$CAPASS"}

trap do_exit 2 3 6 9 11 15 19

do_exit()
{
        STATUS=${1:-0}

        if [ ${DO_RETURN} -eq 1 ];
        then
                return $STATUS
        else
                exit $STATUS
        fi
}

do_error() {
	text="$*"
	text=${text:-Unknown Error}
	echo $text
	do_exit 1
}

MYDIR=$(dirname $0)
TS=$(date +"%Y%m%d")

if [ ! -s ${MYDIR}/../conf.d/ca.conf ]
then
        do_error "You must create a configuration file in ${MYDIR}/../conf.d/ca.conf"
fi

. ${MYDIR}/../conf.d/ca.conf

if [ -n "$*" ]
then
        CUSTOM_HOSTS="$*"
fi


###  Make sure the required indexes are there...
if [ ! -s ${BASE}/db/serial -o ! -s ${BASE}/db/serial ]
then
   SERIAL="${TS}000000"
   echo ${SERIAL} > ${BASE}/db/serial
fi

if [ ! -s ${BASE}/db/certindex.txt ]
then
	touch  ${BASE}/db/certindex.txt
fi

if [ ! -s ${BASE}/db/index.txt ]
then
	touch  ${BASE}/db/index.txt
fi



#######  ROOT certificate


if [ ! -s ${PRIV}/${DOMAIN}-CAcert-key.pem -o ! -s ${CERTS}/${DOMAIN}-CAcert.pem ];
then
echo "Creating root certificate"
        echo "-----"
        echo ""
        echo "<--- Certificate for ${SERVER} --->"
        echo "<--- Certificate for ${DOMAIN}-root --->"
        echo ""
        echo "ORG='${ORG}', OU='${SHORTORG} Root Certificate Authority', CN=${DOMAIN}, email=${CONTACT}"
        echo ""
        # Check for the private key
        test -s ${PRIV}/${DOMAIN}-CAcert-key.pem || openssl genrsa ${PASSOUT} -aes256 -out ${PRIV}/${DOMAIN}-CAcert-key.pem 4096
        test $? -eq 0 || do_error "Couldn't generate the ${DOMAIN}-CAcert-key.pem private certificate"
        # Check for the certificate
        test -s ${CERTS}/${DOMAIN}-CAcert.pem || ${DBG} openssl req ${PASSIN} ${PASSOUT} -config ${CACFG} -new ${DIGEST} -x509 -days 3650 -key ${PRIV}/${DOMAIN}-CAcert-key.pem -extensions v3_ca -out ${CERTS}/${DOMAIN}-CAcert.pem
        test $? -eq 0 || do_error "Couldn't generate the ${DOMAIN}-CAcert.pem public certificate"

${DBG}	openssl x509 ${PASSIN} ${PASSOUT} -in ${CERTS}/${DOMAIN}-CAcert.pem -text -noout
fi

echo ""
echo "-----"
echo "Root certificate checking complete"
echo "-----"
echo ""

######## SIGNING certificate

if [ ! -s ${PRIV}/${DOMAIN}-SIGNcert-key.pem -o ! -s ${CERTS}/${DOMAIN}-SIGNcert.pem ];
then
echo "Creating Intermediate Signing certificate"
        echo "-----"
        echo ""
        echo "<--- Certificate for ${SERVER} --->"
        echo "<--- Certificate for ${DOMAIN}-root --->"
        echo ""
        echo "ORG='${ORG}', OU='${SHORTORG} Intermediate Signing Authority', CN=signing.${DOMAIN}, email=${CONTACT}"
        echo ""

# Create the intermediate private key 
        test -s ${PRIV}/${DOMAIN}-SIGNcert-key.pem || ${DBG} openssl genrsa ${PASSOUT} -aes256 -out ${PRIV}/${DOMAIN}-SIGNcert-key.pem 4096
        test $? -eq 0 || do_error "Couldn't generate the ${DOMAIN}-SIGNcert-key.pem private certificate"
# Create the intermediate SIGNING request
        test -s ${CSRS}/${DOMAIN}-SIGNcert.csr || ${DBG} openssl req -config ${SIGNCFG} ${PASSIN} ${PASSOUT} -key ${PRIV}/${DOMAIN}-SIGNcert-key.pem -extensions v3_ca_req -new ${DIGEST} -out ${CSRS}/${DOMAIN}-SIGNcert.csr
        test $? -eq 0 || do_error "Couldn't generate the ${DOMAIN}-SIGNcert.pem certificate request"
# Create the signed SIGNING certificate
        test -s ${CERTS}/${DOMAIN}-SIGNcert.pem || ${DBG} openssl ca -config ${SIGNCFG} ${PASSIN} -extensions v3_int_ca -notext -in ${CSRS}/${DOMAIN}-SIGNcert.csr -out ${CERTS}/${DOMAIN}-SIGNcert.pem 
        test $? -eq 0 || do_error "Couldn't generate the ${DOMAIN}-SIGNcert.pem certificate"

${DBG}	openssl x509 ${PASSIN} ${PASSOUT} -in ${CERTS}/${DOMAIN}-SIGNcert.pem -text -noout
fi

# Create the certificate chain file
if [ ! -r ${CERTS}/${DOMAIN}-chain.pem ]
then
	# Order matters! issuer chain, then trust chain, then anchor chain, then CA chain...
	cat ${CERTS}/${DOMAIN}-SIGNcert.pem ${CERTS}/${DOMAIN}-CAcert.pem  > ${CERTS}/${DOMAIN}-chain.pem
fi
	
echo ""
echo "-----"
echo "Signing certificate checking complete"
echo "-----"
echo ""

for SERVER in ${HOSTS} ${CUSTOM_HOSTS}
  do
    if [ ! -r ${CERTS}/${SERVER}.crt ];
    then
        echo "-----"
        echo ""
        echo "<--- Certificate for ${SERVER} --->"
        echo ""
        if [ -s ${CBASE}/${SERVER}.cnf ]
        then
                CONF=${CBASE}/${SERVER}.cnf
                PROMPT="-batch"
        else
                CONF=${SIGNCFG}
                PROMPT=""
        fi

# Create the server private key 
        test -s ${PRIV}/${SERVER}-key.pem || ${DBG} openssl genrsa ${PASSOUT} -aes256 -out ${PRIV}/${SERVER}-key.pem 4096
        test $? -eq 0 || do_error "Couldn't generate the ${SERVER}-key.pem private certificate"

# Create the server certificate request
        test -s ${CSRS}/${SERVER}.csr || ${DBG} openssl req -config ${CONF} ${PROMPT} ${PASSIN} ${PASSOUT} -key ${PRIV}/${SERVER}-key.pem -new ${DIGEST} -out ${CSRS}/${SERVER}.csr
        test $? -eq 0 || do_error "Couldn't generate the ${SERVER}-key.pem private certificate"

# Create the signed certificate
        test -s ${CERTS}/${SERVER}.crt || ${DBG} openssl ca -config ${CONF} ${PROMPT} ${PASSIN} -extensions server_cert -notext -in ${CSRS}/${SERVER}.csr -out ${CERTS}/${SERVER}.crt 
        test $? -eq 0 || do_error "Couldn't generate the ${SERVER}.pem public certificate"

${DBG}	openssl x509 ${PASSIN} -in ${CERTS}/${SERVER}.crt -text -noout
        test $? -eq 0 || exit
        echo "----"
        echo ""
    fi
done

for EMAIL in ${EMAIL_CERTS}
  do
    if [ ! -s ${CERTS}/${EMAIL}.p12 ];
    then
        echo "-----"
        echo ""
        echo "<--- Certificate for ${EMAIL} --->"
        echo ""
        if [ -s ${CBASE}/${EMAIL}.cnf ]
        then
                CONF=${CBASE}/${EMAIL}.cnf
        else
                CONF=${CBASE}/emails.cnf
        fi
	DAYS="$(grep -i default_days ${CONF} | cut -f 2 -d= | awk '{print $1}')"
	DAYS="${DAYS:-365}"	# default to 365 if not set.
	DAYS="-days ${DAYS}"

# Create the email private key 
        test -s ${PRIV}/${EMAIL}-key.pem || ${DBG} openssl genrsa ${PASSOUT} -des3 -out ${PRIV}/${EMAIL}-key.pem 4096
        test $? -eq 0 || do_error "Couldn't generate the ${EMAIL}-key.pem private certificate"

# Create the email certificate request
        test -s ${CSRS}/${EMAIL}.csr || ${DBG} openssl req -config ${CONF} ${PASSIN} ${PASSOUT} -key ${PRIV}/${EMAIL}-key.pem -new ${DIGEST} -out ${CSRS}/${EMAIL}.csr
        test $? -eq 0 || do_error "Couldn't generate the ${EMAIL}-key.pem private certificate"

# Create the email certificate
        if [ ! -s ${CERTS}/${EMAIL}.crt ];
        then
        	export OPENSSL_CONF=${CONF}
        	${DBG} openssl x509 -req -in ${CSRS}/${EMAIL}.csr ${PASSIN} -out ${CERTS}/${EMAIL}.crt ${DAYS} \
        	   -CA ${CERTS}/${DOMAIN}-SIGNcert.pem -CAkey ${PRIV}/${DOMAIN}-SIGNcert-key.pem -CAserial ${BASE}/db/serial \
        	   -extensions user_cert \
        	   -setalias "${EMAIL} S/MIME Certificate" -addtrust emailProtection -addreject serverAuth -trustout
	        test $? -eq 0 || do_error "Couldn't generate the ${EMAIL}.pem public certificate"
	fi

# Export the certificate in SMIME format
        if [ ! -s ${CERTS}/${EMAIL}.p12 ];
        then
        	export OPENSSL_CONF=${CONF}
        	# should we chain the public root+signing CA certs here?
		${DBG} openssl pkcs12 ${PASSIN} ${PASSOUT} -export -in ${CERTS}/${EMAIL}.crt -name "${EMAIL} S/MIME Certificate" -inkey ${PRIV}/${EMAIL}-key.pem -out ${CERTS}/${EMAIL}.p12
		test $? -eq 0 || do_error "Couldn't generate the ${EMAIL}.pem PKCS12 certificate"
	fi

${DBG}	openssl x509 ${PASSIN} -in ${CERTS}/${EMAIL}.crt -text -noout
        test $? -eq 0 || exit
        echo "----"
        echo ""
    fi
done


echo ""
echo "<---  DONE --->"
echo ""
echo "For ubuntu/debian systems, "
echo "copy the new .crt file to /usr/local/share/ca-certificates/"
echo "then run 'update-ca-certificates'  to install them in the global file"
echo ""
echo "For Apache server, to remove the requirement for passwords on startup:"
echo "openssl rsa -in secret-key.pem -out secret-key-nopw.pem"
