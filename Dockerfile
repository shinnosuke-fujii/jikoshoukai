# syntax=docker/dockerfile:1
# check=error=true

# ===== Base stage =====
ARG RUBY_VERSION=3.2.6
FROM docker.io/library/ruby:${RUBY_VERSION}-slim AS base

# Rails app lives here
WORKDIR /rails

# Runtime packages (nodejs も入れる／pg は libpq5 が必要)
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      curl \
      libjemalloc2 \
      libvips \
      libpq5 \
      nodejs \
      tzdata && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Production env / bundler config
ENV RAILS_ENV=production \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development test"

# ===== Build stage =====
FROM base AS build

# Build toolchain & headers for native gems (pg など)
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential \
      git \
      pkg-config \
      libpq-dev \
      libyaml-dev && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# 先に Gem だけ入れてキャッシュを効かせる
COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

# アプリ本体
COPY . .

# bootsnap でアプリコードをプリコンパイル
RUN bundle exec bootsnap precompile app/ lib/

# --- ここがポイント ---
# ビルド時に RAILS_MASTER_KEY を渡してアセットをプリコンパイル
ARG RAILS_MASTER_KEY
ENV RAILS_MASTER_KEY=${RAILS_MASTER_KEY}
RUN bundle exec rails assets:precompile

# ===== Final stage =====
FROM base

# gems とアプリをコピー
COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

# 非rootで実行
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    chown -R rails:rails db log storage tmp
USER 1000:1000

# DB準備エントリポイント
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Thruster で起動（必要に応じて変更可）
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
