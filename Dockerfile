# syntax=docker/dockerfile:1
# check=error=true

# ===== Base stage =====
ARG RUBY_VERSION=3.2.6
FROM docker.io/library/ruby:${RUBY_VERSION}-slim AS base
WORKDIR /rails

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      curl libjemalloc2 libvips libpq5 nodejs tzdata && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV RAILS_ENV=production \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development test"

# ===== Build stage =====
FROM base AS build
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git pkg-config libpq-dev libyaml-dev && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

COPY . .
RUN bundle exec bootsnap precompile app/ lib/
# （ここで assets:precompile は実行しない）

# ===== Final stage =====
FROM base

# gems とアプリをコピー
COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

# 起動ユーザーに必要ディレクトリの書き込み権限を付与
RUN mkdir -p tmp/pids tmp/cache tmp/sockets public/assets && \
    chown -R rails:rails tmp log storage public

# 非rootで実行
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    chown -R rails:rails db
USER 1000:1000

ENTRYPOINT ["/rails/bin/docker-entrypoint"]
EXPOSE 80
CMD ["bash", "-lc", "bin/rails assets:precompile && ./bin/thrust ./bin/rails server"]

# 起動時にプリコンパイル（ここなら RAILS_MASTER_KEY は通常の環境変数でOK）
CMD ["bash", "-lc", "bin/rails assets:precompile && ./bin/thrust ./bin/rails server"]
