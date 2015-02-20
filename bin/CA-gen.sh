#!/bin/sh
HOST=$(hostname)
PROG="${0##*/}"
DO_RETURN=${SHLVL}

#DBG="echo"
##########################

trap do_exit SIGINT SIGTERM SIGKILL SIGQUIT SIGABRT SIGSTOP SIGSEGV

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

if [ ! -r ${MYDIR}/../conf.d/ca.conf ]
then
        do_error "You must create a configuration file in ${MYDIR}/../conf.d/ca.conf"
fi

. ${MYDIR}/../conf.d/ca.conf


if [ -n "$*" ]
then
        CUSTOM_HOSTS="$*"
fi


###  Make sure the required indexes are there...
if [ ! -r ${BASE}/db/serial -o ! -s ${BASE}/db/serial ]
then
   SERIAL="${TS}000000"
   echo ${SERIAL} > ${BASE}/db/serial
fi

if [ ! -r ${BASE}/db/certindex.txt ]
then
	touch  ${BASE}/db/certindex.txt
fi

if [ ! -r ${BASE}/db/index.txt ]
then
	touch  ${BASE}/db/index.txt
fi



#######  ROOT certificate


if [ ! -r ${PRIV}/${DOMAIN}-CAcert-key.pem -o ! -r ${CERTS}/${DOMAIN}-CAcert.pem ];
then
echo "Creating root certificate"
        echo "-----"
        echo ""
        echo "<--- Certificate for ${SERVER} --->"
        echo "<--- Certificate for ${DOMAIN}-root --->"
        echo ""
        echo "ORG='${ORG}', OU='Root Certificate Authority', CN=${DOMAIN}, email=${CONTACT}"
        echo ""
        # Check for the private key
        test -r ${PRIV}/${DOMAIN}-CAcert-key.pem || openssl genrsa -aes256 -out ${PRIV}/${DOMAIN}-CAcert-key.pem 4096
        test $? -eq 0 || do_error "Couldn't generate the ${DOMAIN}-CAcert-key.pem private certificate"
        # Check for the certificate
        test -r ${CERTS}/${DOMAIN}-CAcert.pem || ${DBG} openssl req -config ${CACFG} -new ${DIGEST} -x509 -days 3650 -key ${PRIV}/${DOMAIN}-CAcert-key.pem -extensions v3_ca -out ${CERTS}/${DOMAIN}-CAcert.pem
        test $? -eq 0 || do_error "Couldn't generate the ${DOMAIN}-CAcert.pem public certificate"

${DBG}	openssl x509 -in ${CERTS}/${DOMAIN}-CAcert.pem -text -noout
fi

echo ""
echo "-----"
echo "Root certificate checking complete"
echo "-----"
echo ""

######## SIGNING certificate

if [ ! -r ${PRIV}/${DOMAIN}-SIGNcert-key.pem -o ! -r ${CERTS}/${DOMAIN}-SIGNcert.pem ];
then
echo "Creating Intermediate Signing certificate"
        echo "-----"
        echo ""
        echo "<--- Certificate for ${SERVER} --->"
        echo "<--- Certificate for ${DOMAIN}-root --->"
        echo ""
        echo "ORG='${ORG}', OU='Intermediate Signing Authority', CN=signing.${DOMAIN}, email=${CONTACT}"
        echo ""

# Create the intermediate private key 
        test -r ${PRIV}/${DOMAIN}-SIGNcert-key.pem || ${DBG} openssl genrsa -aes256 -out ${PRIV}/${DOMAIN}-SIGNcert-key.pem 4096
        test $? -eq 0 || do_error "Couldn't generate the ${DOMAIN}-SIGNcert-key.pem private certificate"
# Create the intermediate SIGNING request
        test -r ${CSRS}/${DOMAIN}-SIGNcert.csr || ${DBG} openssl req -config ${SIGNCFG} -key ${PRIV}/${DOMAIN}-SIGNcert-key.pem -new ${DIGEST} -out ${CSRS}/${DOMAIN}-SIGNcert.csr
        test $? -eq 0 || do_error "Couldn't generate the ${DOMAIN}-SIGNcert.pem certificate request"
# Create the signed SIGNING certificate
        test -r ${CERTS}/${DOMAIN}-SIGNcert.pem || ${DBG} openssl ca -config ${SIGNCFG} -extensions v3_ca -notext -in ${CSRS}/${DOMAIN}-SIGNcert.csr -out ${CERTS}/${DOMAIN}-SIGNcert.pem 
        test $? -eq 0 || do_error "Couldn't generate the ${DOMAIN}-SIGNcert.pem certificate"

${DBG}	openssl x509 -in ${CERTS}/${DOMAIN}-SIGNcert.pem -text -noout
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
        if [ -r ${CBASE}/${SERVER}.cnf ]
        then
                CONF=${CBASE}/${SERVER}.cnf
        else
                CONF=${SIGNCFG}
        fi

# Create the intermediate private key 
        test -r ${PRIV}/${SERVER}-key.pem || ${DBG} openssl genrsa -aes256 -out ${PRIV}/${SERVER}-key.pem 4096
        test $? -eq 0 || do_error "Couldn't generate the ${SERVER}-key.pem private certificate"

# Create the intermediate SIGNING request
        test -r ${CSRS}/${SERVER}.csr || ${DBG} openssl req -config ${CONF} -key ${PRIV}/${SERVER}-key.pem -new ${DIGEST} -out ${CSRS}/${SERVER}.csr
#        test -r ${CSRS}/${SERVER}.csr || ${DBG} openssl req -config ${CONF} -new -nodes -keyout ${PRIV}/${SERVER}-key.pem -out ${CSRS}/${SERVER}.csr
        test $? -eq 0 || do_error "Couldn't generate the ${SERVER}-key.pem private certificate"

# Create the signed SIGNING certificate
        test -r ${CERTS}/${SERVER}.crt || ${DBG} openssl ca -config ${CONF} -notext -in ${CSRS}/${SERVER}.csr -out ${CERTS}/${SERVER}.crt 
#        test -r ${CERTS}/${SERVER}.crt || ${DBG} openssl ca -config ${CONF} -md ${DIGEST} -out ${CERTS}/${SERVER}.crt -days 3650 -infiles ${CSRS}/${SERVER}.csr
        test $? -eq 0 || do_error "Couldn't generate the ${SERVER}.pem public certificate"

${DBG}	openssl x509 -in ${CERTS}/${SERVER}.crt -text -noout
        test $? -eq 0 || exit
        echo "----"
        echo ""
    fi
done

for EMAIL in ${EMAIL_CERTS}
  do
    if [ ! -r ${CERTS}/${EMAIL}.crt ];
    then
        echo "-----"
        echo ""
        echo "<--- Certificate for ${EMAIL} --->"
        echo ""
        if [ -r ${CBASE}/${EMAIL}.cnf ]
        then
                CONF=${CBASE}/${EMAIL}.cnf
        else
                CONF=${CBASE}/emails.cnf
        fi

# Create the intermediate private key 
        test -r ${PRIV}/${EMAIL}-key.pem || ${DBG} openssl genrsa -des3 -out ${PRIV}/${EMAIL}-key.pem 4096
        test $? -eq 0 || do_error "Couldn't generate the ${EMAIL}-key.pem private certificate"

# Create the intermediate SIGNING request
        test -r ${CSRS}/${EMAIL}.csr || ${DBG} openssl req -config ${CONF} -key ${PRIV}/${EMAIL}-key.pem -new ${DIGEST} -out ${CSRS}/${EMAIL}.csr
        test $? -eq 0 || do_error "Couldn't generate the ${EMAIL}-key.pem private certificate"

# Create the signed SIGNING certificate
        test -r ${CERTS}/${EMAIL}.crt || ${DBG} \
        	openssl x509 -req -in ${CSRS}/${EMAIL}.csr -out ${CERTS}/${EMAIL}.crt \
        	   -CA ${CERTS}/${DOMAIN}-SIGNcert.pem -CAkey ${PRIV}/${DOMAIN}-SIGNcert-key.pem -CAserial ${BASE}/db/serial \
        	   -setalias "${DOMAIN} S/MIME Certificate" -addtrust emailProtection -addreject serverAuth -trustout
        test $? -eq 0 || do_error "Couldn't generate the ${EMAIL}.pem public certificate"

# Export the certificate in SMIME format
	test -r ${CERTS}/${EMAIL}.p12 || ${DBG} openssl pkcs12 -export -in ${CERTS}/${EMAIL}.crt -inkey ${PRIV}/${EMAIL}-key.pem -out ${CERTS}/${EMAIL}.p12
	test $? -eq 0 || do_error "Couldn't generate the ${EMAIL}.pem PKCS12 certificate"

${DBG}	openssl x509 -in ${CERTS}/${EMAIL}.crt -text -noout
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
