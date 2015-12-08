# Create a NodePoint Docker image
FROM centos:7
MAINTAINER dendory@live.ca
RUN cd /tmp && yum install httpd -y && yum install mod_ssl -y && yum install wget -y && wget https://nodepoint.ca/nodepoint.tar && tar xf nodepoint.tar && mv nodepoint/www /var/www/nodepoint && mv nodepoint/nodepoint.cfg /var/www/ && mv nodepoint/db /var/www/db && mv nodepoint/uploads /var/www/uploads && wget http://public.dendory.net/httpd.centos.example && yes|cp httpd.centos.example /etc/httpd/conf/httpd.conf
EXPOSE 80
EXPOSE 443
CMD ["/usr/sbin/httpd", "-D", "FOREGROUND"]

