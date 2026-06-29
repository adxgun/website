FROM hugomods/hugo:git AS build
WORKDIR /app
COPY . .
RUN git submodule update --init --recursive && \
    hugo --gc --minify

FROM alpine:3
COPY --from=build /app/public /srv/