FROM hugomods/hugo:git AS build
WORKDIR /app
COPY . .
RUN git clone https://github.com/tomfran/typo themes/typo && \
    hugo --gc --minify

FROM alpine:3
COPY --from=build /app/public /srv/