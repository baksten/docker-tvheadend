############## build stages ##############
FROM ghcr.io/linuxserver/baseimage-alpine:3.15 AS amd64-buildstage
FROM ghcr.io/linuxserver/baseimage-alpine:arm32v7-3.15 AS armv7-buildstage
FROM ghcr.io/linuxserver/baseimage-alpine:arm64v8-3.15 as arm64-buildstage

FROM ${TARGETARCH}${TARGETVARIANT}-buildstage AS buildstage
# package versions
ARG ARGTABLE_VER="2.13"
ARG XMLTV_VER="v1.0.0"

# environment settings
ARG TARGETARCH
ARG TARGETVARIANT
ARG TZ="Europe/Oslo"
ARG TVHEADEND_COMMIT
ENV HOME="/config"

RUN \
  echo "**** install build packages ****" && \
  apk add --no-cache \
    autoconf \
    automake \
    bsd-compat-headers \
    bzip2 \
    cmake \
    curl \
    ffmpeg-dev \
    file \
    findutils \
    g++ \
    gcc \
    gettext-dev \
    git \
    gnu-libiconv-dev \
    gzip \
    jq \
    libcurl \
    libgcrypt-dev \
    libhdhomerun-dev \
    libtool \
    libvpx-dev \
    libxml2-dev \
    libxslt-dev \
    linux-headers \
    make \
    openssl-dev \
    opus-dev \
    patch \
    pcre2-dev \
    perl-archive-zip \
    perl-boolean \
    perl-capture-tiny \
    perl-cgi \
    perl-compress-raw-zlib \
    perl-date-manip \
    perl-datetime \
    perl-datetime-format-strptime \
    perl-datetime-timezone \
    perl-dbd-sqlite \
    perl-dbi \
    perl-dev \
    perl-digest-sha1 \
    perl-doc \
    perl-file-slurp \
    perl-file-temp \
    perl-file-which \
    perl-getopt-long \
    perl-html-parser \
    perl-html-tree \
    perl-http-cookies \
    perl-io \
    perl-io-html \
    perl-io-socket-ssl \
    perl-io-stringy \
    perl-json \
    perl-json-xs \
    perl-libwww \
    perl-lingua-en-numbers-ordinate \
    perl-lingua-preferred \
    perl-list-moreutils \
    perl-lwp-useragent-determined \
    perl-module-build \
    perl-module-pluggable \
    perl-net-ssleay \
    perl-parse-recdescent \
    perl-path-class \
    perl-scalar-list-utils \
    perl-term-progressbar \
    perl-term-readkey \
    perl-test-exception \
    perl-test-requires \
    perl-timedate \
    perl-try-tiny \
    perl-unicode-string \
    perl-xml-libxml \
    perl-xml-libxslt \
    perl-xml-parser \
    perl-xml-sax \
    perl-xml-treepp \
    perl-xml-twig \
    perl-xml-writer \
    pkgconf \
    pngquant \
    python3 \
    sdl-dev \
    tar \
    uriparser-dev \
    wget \
    x264-dev \
    x265-dev \
    zlib-dev

RUN if [ "$TARGETARCH$TARGETVARIANT" = "amd64" ]; then \
    echo "**** install additional build packages for amd64 ****" && \
    apk add --no-cache \
      libva-dev; \
  fi

#Download linuxserver/tvheadend git
RUN \
  echo "**** download linuxserver/docker-tvheadend ****" && \
  git clone https://github.com/linuxserver/docker-tvheadend.git /tmp/docker-tvheadend

# copy patches
COPY patches/ /tmp/patches/

RUN \
  echo "**** move patches ****" && \
  mv /tmp/docker-tvheadend/patches/* /tmp/patches/

RUN \
  echo "**** remove musl iconv.h and replace with gnu-iconv.h ****" && \
  rm -rf /usr/include/iconv.h && \
  cp /usr/include/gnu-libiconv/iconv.h /usr/include/iconv.h

RUN \
  echo "**** install perl modules for xmltv ****" && \
  curl -s -L https://cpanmin.us | perl - App::cpanminus && \
  cpanm --installdeps /tmp/patches

RUN \
  echo "**** compile XMLTV ****" && \
  git clone https://github.com/XMLTV/xmltv.git /tmp/xmltv && \
  cd /tmp/xmltv && \
  git checkout ${XMLTV_VER} && \
  echo "**** Perl 5.26 fixes for XMTLV ****" && \
  sed "s/use POSIX 'tmpnam';//" -i filter/tv_to_latex && \
  sed "s/use POSIX 'tmpnam';//" -i filter/tv_to_text && \
  sed "s/\(lib\/set_share_dir.pl';\)/.\/\1/" -i grab/it/tv_grab_it.PL && \
  sed "s/\(filter\/Grep.pm';\)/.\/\1/" -i filter/tv_grep.PL && \
  sed "s/\(lib\/XMLTV.pm.in';\)/.\/\1/" -i lib/XMLTV.pm.PL && \
  sed "s/\(lib\/Ask\/Term.pm';\)/.\/\1/" -i Makefile.PL && \
  PERL5LIB=`pwd` && \
  echo -e "yes" | perl Makefile.PL PREFIX=/usr/ INSTALLDIRS=vendor && \
  make -j$(nproc --ignore=1) && \
  make test && \
  make DESTDIR=/tmp/xmltv-build install

RUN \
  echo "**** build libdvbcsa ****" && \
  git clone https://github.com/glenvt18/libdvbcsa.git /tmp/libdvbcsa && \
  cd /tmp/libdvbcsa && \
  git apply /tmp/patches/libdvbcsa.patch && \
  ./bootstrap && \
  ./configure \
    --prefix=/usr \
    --sysconfdir=/etc \
    --mandir=/usr/share/man \
    --infodir=/usr/share/info \
    --localstatedir=/var && \
  make -j$(nproc --ignore=1) && \
  make check && \
  make DESTDIR=/tmp/libdvbcsa-build install && \
  echo "**** copy to /usr for tvheadend dependency ****" && \
  cp -pr /tmp/libdvbcsa-build/usr/* /usr/
 
RUN \
  echo "**** build tvheadend ****" && \
  if [ -z ${TVHEADEND_COMMIT+x} ]; then \
    TVHEADEND_COMMIT=$(curl -sX GET https://api.github.com/repos/tvheadend/tvheadend/commits/master \
    | jq -r '. | .sha'); \
  fi && \
  mkdir -p \
    /tmp/tvheadend && \
  git clone https://github.com/tvheadend/tvheadend.git /tmp/tvheadend && \
  cd /tmp/tvheadend && \
  git fetch && \
  git checkout ${TVHEADEND_COMMIT} && \
  echo "**** patch tvheadend ****" && \
  git apply /tmp/patches/tvheadend43.patch && \
  echo "**** configure tvheadend ****" && \
  ./configure \
    `#Encoding` \
    --disable-ffmpeg_static \
    --disable-libfdkaac_static \
    --disable-libtheora_static \
    --disable-libopus_static \
    --disable-libvorbis_static \
    --disable-libvpx_static \
    --disable-libx264_static \
    --disable-libx265_static \
    --disable-libfdkaac \
    --enable-libopus \
    --enable-libvorbis \
    --enable-libvpx \
    --enable-libx264 \
    --enable-libx265 \
    \
    `#Options` \
    --disable-avahi \
    --disable-dbus_1 \
    --disable-bintray_cache \
    --disable-execinfo \
    --disable-hdhomerun_static \
    --enable-hdhomerun_client \
    --enable-libav \
    --enable-pngquant \
    --enable-trace \
    $([[ "$TARGETARCH$TARGETVARIANT" = "amd64" ]] && echo '--enable-vaapi' || echo "") \
    $([[ "$TARGETARCH$TARGETVARIANT" = "armv7" ]] && echo '--nowerror' || echo "") \
    --infodir=/usr/share/info \
    --localstatedir=/var \
    --mandir=/usr/share/man \
    --prefix=/usr \
    --python=python3 \
    --sysconfdir=/config && \
  echo "**** compile tvheadend ****" && \
  make -j$(nproc --ignore=1) && \
  make DESTDIR=/tmp/tvheadend-build install

RUN \
  echo "**** compile argtable2 ****" && \
  ARGTABLE_VER1="${ARGTABLE_VER//./-}" && \
  mkdir -p \
    /tmp/argtable && \
  curl -s -o \
  /tmp/argtable-src.tar.gz -L \
    "https://sourceforge.net/projects/argtable/files/argtable/argtable-${ARGTABLE_VER}/argtable${ARGTABLE_VER1}.tar.gz" && \
  tar xf \
  /tmp/argtable-src.tar.gz -C \
    /tmp/argtable --strip-components=1 && \
  cp /tmp/patches/config.* /tmp/argtable && \
  cd /tmp/argtable && \
  ./configure \
    --prefix=/usr && \
  make -j$(nproc --ignore=1) && \
  make check && \
  make DESTDIR=/tmp/argtable-build install && \
  echo "**** copy to /usr for comskip dependency ****" && \
  cp -pr /tmp/argtable-build/usr/* /usr/

RUN \
  echo "***** compile comskip ****" && \
  git clone https://github.com/erikkaashoek/Comskip /tmp/comskip && \
  cd /tmp/comskip && \
  ./autogen.sh && \
  ./configure \
    --bindir=/usr/bin \
    --sysconfdir=/config/comskip && \
  make -j$(nproc --ignore=1) && \
  make DESTDIR=/tmp/comskip-build install


############## picons stage ##############
# built by https://github.com/linuxserver/picons-builder
FROM ghcr.io/linuxserver/picons-builder AS piconsstage


############## runtime stages ##############
FROM ghcr.io/linuxserver/baseimage-alpine:3.15 AS amd64-runtime
FROM ghcr.io/linuxserver/baseimage-alpine:arm32v7-3.15 AS armv7-runtime
FROM ghcr.io/linuxserver/baseimage-alpine:arm64v8-3.15 as arm64-runtime

FROM ${TARGETARCH}${TARGETVARIANT}-runtime AS runtime
# set version label
ARG BUILD_DATE
ARG VERSION
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="saarg"

# environment settings
ARG TARGETARCH
ARG TARGETVARIANT
ENV HOME="/config"

RUN \
  echo "**** install runtime packages ****" && \
  apk add --no-cache \
    bsd-compat-headers \
    bzip2 \
    curl \
    ffmpeg \
    ffmpeg-libs \
    gnu-libiconv \
    gzip \
    libcrypto1.1 \
    libcurl \
    libhdhomerun-libs \
    libssl1.1 \
    libvpx \
    libxml2 \
    libxslt \
    linux-headers \
    openssl \
    opus \
    pcre2 \
    perl \
    perl-archive-zip \
    perl-boolean \
    perl-capture-tiny \
    perl-cgi \
    perl-compress-raw-zlib \
    perl-date-manip \
    perl-datetime \
    perl-datetime-format-strptime \
    perl-datetime-timezone \
    perl-dbd-sqlite \
    perl-dbi \
    perl-digest-sha1 \
    perl-doc \
    perl-file-slurp \
    perl-file-temp \
    perl-file-which \
    perl-getopt-long \
    perl-html-parser \
    perl-html-tree \
    perl-http-cookies \
    perl-io \
    perl-io-html \
    perl-io-socket-ssl \
    perl-io-stringy \
    perl-json \
    perl-json-xs \
    perl-libwww \
    perl-lingua-en-numbers-ordinate \
    perl-lingua-preferred \
    perl-list-moreutils \
    perl-lwp-useragent-determined \
    perl-module-build \
    perl-module-pluggable \
    perl-net-ssleay \
    perl-parse-recdescent \
    perl-path-class \
    perl-scalar-list-utils \
    perl-term-progressbar \
    perl-term-readkey \
    perl-test-exception \
    perl-test-requires \
    perl-timedate \
    perl-try-tiny \
    perl-unicode-string \
    perl-xml-libxml \
    perl-xml-libxslt \
    perl-xml-parser \
    perl-xml-sax \
    perl-xml-treepp \
    perl-xml-twig \
    perl-xml-writer \
    py3-requests \
    python3 \
    tar \
    uriparser \
    wget \
    x264 \
    x265 \
    zlib

RUN if [ "$TARGETARCH$TARGETVARIANT" = "amd64" ]; then \
    echo "**** install additional build packages for amd64 ****" && \
    apk add --no-cache \
      libva \
      libva-intel-driver \
      intel-media-driver \
      mesa-dri-ati; \ 
  fi

# copy local files and buildstage artifacts
COPY --from=buildstage /tmp/docker-tvheadend/root/ /
COPY --from=buildstage /tmp/libdvbcsa-build/usr/ /usr/
COPY --from=buildstage /tmp/argtable-build/usr/ /usr/
COPY --from=buildstage /tmp/comskip-build/usr/ /usr/
COPY --from=buildstage /tmp/tvheadend-build/usr/ /usr/
COPY --from=buildstage /tmp/xmltv-build/usr/ /usr/
COPY --from=buildstage /usr/local/share/man/ /usr/local/share/man/
COPY --from=buildstage /usr/local/share/perl5/ /usr/local/share/perl5/
COPY --from=piconsstage /picons.tar.bz2 /picons.tar.bz2

# ports and volumes
EXPOSE 9981 9982
VOLUME /config
