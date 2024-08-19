#!/bin/sh

main() {
    cloudfront_dist_id="$1"

    if echo "$cloudfront_dist_id" | grep -oE '([A-Za-z0-9\-\_]+\.){2}[a-z]+' >/dev/null; then
        domain="$cloudfront_dist_id"
        echo "retrieving distribution id for domain $domain..." >&2

        cloudfront_dist_id=$(aws --output=json cloudfront list-distributions | jq \
            -r ".DistributionList.Items[] | select(.Aliases.Items[] == \"$domain\") | .Id")
    fi

    set +e

    printf "queue \\\ \n 1. update-distribution \\\ \n 2. start-invalidate-content-process \\\ \n 3. wait-invalidation-propagation\n\n" >&2
    printf "[cloudfront distribution id: %s]\n\n" "$cloudfront_dist_id"

    data=$(aws cloudfront get-distribution-config --id "$cloudfront_dist_id" --output json)

    etag=$(echo "$data" | jq -r '.ETag')
    dist_config=$(echo "$data" | jq -r '.DistributionConfig')

    aws cloudfront update-distribution --id "$cloudfront_dist_id" --if-match "$etag" --distribution-config "$dist_config" >/dev/null
    echo "distribution updated..." >&2

    invalidation_id=$(aws cloudfront --output json create-invalidation --distribution-id "$cloudfront_dist_id" --paths "/*" | jq -r '.Invalidation.Id')
    echo "invalidating old distribution content..." >&2

    start=$(date +%s)

    echo "waiting for the invalidation process to complete..." >&2

    while [ ! "$(aws cloudfront --output json get-invalidation --id "$invalidation_id" --distribution-id "$cloudfront_dist_id" | jq -r '.Invalidation.Status')" = 'Completed' ]; do
        printf "" >&2
    done

    end=$(date +%s)
    printf "\n\nqueue completed in %ss\n" "$((end - start))" >&2
}

main "$@"
