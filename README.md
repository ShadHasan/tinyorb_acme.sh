## TINYORB ACME

--------------------------------
Tinyorb ACME has been forked from ACMESH project, in order to integrate the `Tinyorb dnsapi`. 

Source code [link](https://ShadHasan@bitbucket.org/tinyorb_team/tinyorb_dnsapi.git)


### How to use as cli
1. Install acme.sh, go to `acme.sh/` folder and run below command
   ```
   $> ./acme.sh --install -m <your email account>
   ```
2. If dnsapi has not been initiated then first init the dns and zone, go to `acme.sh/dnsapi/` path
   ```
   $> ./dnsapi_to init dns
   $> ./dnsapi_to init zone
   ```
3. Add dns server detail as NS record to the dns provider site. Note `ns1.<zone domain>` is your primary dns serer and `ns2.<zone domain>` is alternate dns server 
4. Command to generate certificate
   1. Directly to zone
   ```
   $> ./acme.sh --issue --dns dns_to -d $zone -d *.$zone 
   ```
   2. Using as an alias
      With reference of acme [wiki](https://github.com/acmesh-official/acme.sh/wiki/DNS-alias-mode).
      This feature helps certificate generation without exposing api, or other mean of dns.
   
      1. For all domain you have to create CNAME record
      2. First set domain CNAME to the expose domain as `_acme-challenge`, detail are in below:
         ```
         For example, acme.sh expose domain aliasDomainForValidationOnly.com for cert generator and you want to generate for example.com:
         
         _acme-challenge.example.com =>   _acme-challenge.aliasDomainForValidationOnly.com

         or, in standard DNS zone file format, (like ISC BIND or NSD):
      
         `_acme-challenge.example.com	IN	CNAME	_acme-challenge.aliasDomainForValidationOnly.com.`
         ```
      3. Use the command to generate the certificate like
         ```
         $> acme.sh --issue  \
         -d  example.com --challenge-alias aliasDomainForValidationOnly.com --dns dns_to \
         -d  *.example.com \ 
         ```
         Note: In our case `aliasDomainForValidationOnly.com` should replace with $zone
         