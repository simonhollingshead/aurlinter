<?xml version="1.0"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
    <xsl:output method="text" omit-xml-declaration="yes"/>
    <xsl:template match="/">
        <xsl:for-each select="//tr/td[2]/a/@href">
            <xsl:value-of select="."/>
            <xsl:text></xsl:text>
        </xsl:for-each>
        <xsl:value-of select="//div[@class='pkglist-stats'][1]/p"/>
        <xsl:text></xsl:text>
    </xsl:template>
</xsl:stylesheet>
