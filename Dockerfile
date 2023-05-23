# Базовый образ с КриптоПро
FROM debian:stretch-slim as cryptopro-generic

# Устанавливаем timezone
ENV TZ="Europe/Moscow" \
    docker="1"

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
    echo $TZ > /etc/timezone


ADD dist /tmp/src
RUN cd /tmp/src && \
    tar -xf linux-amd64_deb.tgz && \
    linux-amd64_deb/install.sh

RUN cd /tmp/src && \
    dpkg -i linux-amd64_deb/lsb-cprocsp-devel_5.0.12000-6_all.deb
    # делаем симлинки
RUN set -ex && \
    cd /bin && \    
    ln -s /opt/cprocsp/bin/amd64/certmgr && \
    ln -s /opt/cprocsp/bin/amd64/cpverify && \
    ln -s /opt/cprocsp/bin/amd64/cryptcp && \
    ln -s /opt/cprocsp/bin/amd64/csptest && \
    ln -s /opt/cprocsp/bin/amd64/csptestf && \
    ln -s /opt/cprocsp/bin/amd64/der2xer && \
    ln -s /opt/cprocsp/bin/amd64/inittst && \
    ln -s /opt/cprocsp/bin/amd64/wipefile && \
    ln -s /opt/cprocsp/sbin/amd64/cpconfig && \
    # прибираемся
    rm -rf /tmp/src

# Образ с PHP cli и скриптами
FROM cryptopro-generic
ADD dist /tmp/src
# Изменяем пути к дистрибутиву debian:stretch-slim(перенесен в архив)
RUN set -ex && \
    sed -i s/deb.debian.org/archive.debian.org/g /etc/apt/sources.list && \
    sed -i 's|security.debian.org|archive.debian.org/|g' /etc/apt/sources.list && \
    sed -i '/stretch-updates/d' /etc/apt/sources.list
#обновление и установка пакетов
RUN set -ex && \
    apt-get update && \
    apt-get install -y --no-install-recommends expect && \
    apt-get install -y --no-install-recommends alien && \
    apt-get install -y --no-install-recommends php7.0-cli && \
    apt-get install -y --no-install-recommends php7.0-dev && \
    apt-get install -y --no-install-recommends php7.0-dom && \
    apt-get install -y --no-install-recommends libboost-dev && \
    apt-get install -y --no-install-recommends unzip && \
    apt-get install -y --no-install-recommends g++ && \
    apt-get install -y --no-install-recommends curl && \
    apt-get install -y --no-install-recommends libxml2-dev
    
RUN apt-get install dos2unix
RUN set -ex && \
    cd /tmp/src && \
    tar -xf cades-linux-amd64.tar.gz && \
    dpkg -i cades-linux-amd64/cprocsp-pki-phpcades-64_2.0.14660-1_amd64.deb && \
    dpkg -i cades-linux-amd64/cprocsp-pki-cades-64_2.0.14660-1_amd64.deb
    # меняем Makefile.unix
RUN set -ex && \
    PHP_BUILD=`php -i | grep 'PHP Extension => ' | awk '{print $4}'` && \    
    # /usr/include/php/20151012/
    sed -i "s#PHPDIR=/php#PHPDIR=/usr/include/php/$PHP_BUILD#g" /opt/cprocsp/src/phpcades/Makefile.unix && \
    # копируем недостающую библиотеку
    unlink /opt/cprocsp/lib/amd64/libcppcades.so && \ 
    ln -s /opt/cprocsp/lib/amd64/libcppcades.so.2 /opt/cprocsp/lib/amd64/libcppcades.so && \
    # начинаем сборку
    cd /opt/cprocsp/src/phpcades && \
    # применяем патч
    unzip /tmp/src/php7_support.patch.zip && \
    patch < php7_support.patch && \
    # собираем
    eval `/opt/cprocsp/src/doxygen/CSP/../setenv.sh --64`; make -f Makefile.unix && \
    # делаем симлинк собранной библиотеки
    EXT_DIR=`php -i | grep 'extension_dir => ' | awk '{print $3}'` && \
    mv libphpcades.so "$EXT_DIR" && \
    # включаем расширение
    echo "extension=libphpcades.so" > /etc/php/7.0/cli/php.ini && \
    # проверяем наличие класса CPStore
    php -r "var_dump(class_exists('CPStore'));" | grep -q 'bool(true)'
    # прибираемся
RUN cd / && \
    apt-get purge -y php7.0-dev cprocsp-pki-phpcades-64 lsb-cprocsp-devel g++ && \
    apt-get autoremove -y && \
    rm -rf /opt/cprocsp/src/phpcades && \
    rm -rf /tmp/src && \
    rm -rf /var/lib/apt/lists/

ADD scripts /scripts
ADD www /www
ADD certificates/bundle.zip /certificates/bundle.zip

#конвертация символа переноса строки
RUN dos2unix /scripts/root && \
    dos2unix /scripts/my && \
    dos2unix /scripts/sign && \
    dos2unix /scripts/unsign && \
    dos2unix /scripts/verify && \
    dos2unix /scripts/lib/functions.sh && \
    dos2unix /scripts/lib/colors.sh && \
    dos2unix /scripts/lib/root.exp && \
#установка сертификатов
    curl -sS http://crl.roskazna.ru/crl/ucfk_2023.crt | /scripts/root && \
    curl -sS http://reestr-pki.ru/cdp/guc2022.crt | /scripts/root && \
    cat certificates/bundle.zip | /scripts/my && \
    rm -rf certificates

# composer
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl ca-certificates && \
    # composer
    curl "https://getcomposer.org/installer" > composer-setup.php && \
    php composer-setup.php && \
    rm -f composer-setup.php && \
    chmod +x composer.phar && \
    mv composer.phar /bin/composer && \
    cd /www && composer update
    # прибираемся
# RUN cd / && \
#     apt-get purge -y curl ca-certificates

HEALTHCHECK --interval=60s --timeout=5s CMD ["curl", "-m5", "-f", "http://localhost:8080/healthcheck"]

CMD ["php", "-S", "0.0.0.0:8080", "-t", "/www/public/"]
