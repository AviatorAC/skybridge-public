# AVI Skybridge

## Installation

1. Install node.js
1. Install `yarn` (`npm i -g yarn`)
1. Run `yarn` in the root directory of this project

## Running tests / coverages

`yarn test` / `yarn coverage`

## Deploying

1. Obtain your L1 and L2 RPC urls, as well as your private key in hexadecimal format
1. Run `./deploy.sh <L1_RPC_URL> <L2_RPC_URL> <PRIVATE_KEY>`

## Running the backend

### Requirements

-   a postgresql instance

1. Deploy the contracts as described above
1. cd into the `backend` directory
1. Fill out the correct postgresql connection string in the `.env` file
1. Run `yarn cleanbuild` to build the project
1. Run `yarn start` to start the backend
