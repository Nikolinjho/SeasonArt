const { chromium } = require('/Users/itsnikoko/sputnik/app-customer-next/node_modules/playwright');
const fs = require('node:fs');
(async () => {
  const browser = await chromium.launch({headless: true});
  const page = await browser.newPage({ viewport: {width: 1440, height: 1000}, deviceScaleFactor: 1 });
  const errors=[];
  page.on('pageerror',e=>errors.push(e.message));
  await page.goto('https://koiart.app/', {waitUntil: 'networkidle'});
  await page.getByRole('button', {name: 'No thanks', exact: true}).click();
  await page.screenshot({path: '/tmp/koiart-research/site-full.png', fullPage: true});
  for (const name of ['Snow','Rain','Sakura','Leaves','Fireflies','Starfall']) {
    await page.getByRole('button', {name, exact: true}).click();
    const canvas = page.locator('canvas').first();
    await canvas.scrollIntoViewIfNeeded();
    await page.waitForTimeout(4000);
    await canvas.locator('..').screenshot({path: `/tmp/koiart-research/demo-${name.toLowerCase()}.png`});
  }
  const details = await page.evaluate(() => ({
    title: document.title,
    images: [...document.images].map(i => ({src: i.src, width: i.naturalWidth, height:i.naturalHeight, loaded:i.complete&&i.naturalWidth>0})),
    canvases: document.querySelectorAll('canvas').length,
    hidden: document.hidden,
    canvasPixels: [...document.querySelectorAll('canvas')].map(c=>{const a=c.getContext('2d').getImageData(0,0,c.width,c.height).data;let n=0;for(let i=3;i<a.length;i+=4)if(a[i])n++;return n}),
    text: document.body.innerText
  }));
  fs.writeFileSync('/tmp/koiart-research/page-details.json', JSON.stringify(details,null,2));
  console.log(JSON.stringify({screenshots:7, images:details.images.length, brokenImages:details.images.filter(i=>!i.loaded).length, canvases:details.canvases, hidden:details.hidden,pixels:details.canvasPixels,errors}));
  await browser.close();
})().catch(e => {console.error(e);process.exit(1)});
