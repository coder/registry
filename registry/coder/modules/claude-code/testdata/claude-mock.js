#!/usr/bin/env node

const main = async () => {
  console.log("mocking claude");
  // sleep for 30 minutes
  await new Promise((resolve) => setTimeout(resolve, 30 * 60 * 1000));
};

main();
